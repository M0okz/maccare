import Foundation
import SwiftUI
import Combine

/// Explorateur d'espace disque : mesure un niveau de dossier à la fois (le moteur borne la
/// mesure), laisse descendre dans les plus gros dossiers et remonter via un fil d'ariane.
/// La suppression reste confinée à la racine d'exploration et re-validée par les gardes de sûreté.
@MainActor
final class SpaceModel: ObservableObject {
    /// Un point de départ proposé.
    struct Root: Identifiable, Hashable {
        let name: String
        let path: String
        var id: String { path }
    }

    @Published private(set) var root: Root
    @Published private(set) var stack: [String] = []        // chemins absolus, racine → courant
    @Published private(set) var children: [SpaceChild] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMeasured = false
    @Published private(set) var lastMeasuredAt: Date?
    @Published private(set) var highlightedPath: String?
    enum HoverSource: Equatable { case map, row(String) }
    private var hoverSource: HoverSource?
    @Published private(set) var selectedPath: String?
    /// Progression en direct de la mesure en cours (entrées lues, octets comptés).
    @Published private(set) var liveEntries: UInt64 = 0
    @Published private(set) var liveBytes: UInt64 = 0
    @Published var statusMessage: String?
    @Published var lastReport: RemovalReport?

    var directDelete: Bool { UserDefaults.standard.bool(forKey: "directDelete") }
    /// Mesure en cours : annulée dès qu'on navigue ailleurs, pour libérer le disque tout de suite.
    private var measureTask: EngineTask?

    private struct Snapshot {
        let children: [SpaceChild]
        let date: Date
    }
    private var snapshots: [String: Snapshot] = [:]
    private var snapshotOrder: [String] = []
    private let measureDirectory: @Sendable (String, EngineTask) throws -> [SpaceChild]

    @Published private(set) var roots: [Root]
    @Published private(set) var volumes: [Root]
    private let discoverVolumes: () -> [Root]
    private var volumeNotifications: AnyCancellable?

    init(preferences: FileStoragePreferences = FileStoragePreferences(),
         measure: @escaping @Sendable (String, EngineTask) throws -> [SpaceChild] = { try Engine.measureDir($0, task: $1) },
         volumeProvider: (() -> [Root])? = nil,
         volumeEvents: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        measureDirectory = measure
        let home = NSHomeDirectory()
        func sub(_ c: String) -> String { (home as NSString).appendingPathComponent(c) }
        let discover = volumeProvider ?? { Self.mountedVolumes() }
        discoverVolumes = discover
        let mounted = Self.withStartupDisk(discover())
        volumes = mounted
        let availableRoots = mounted + [
            Root(name: "Dossier personnel", path: home),
            Root(name: "Bureau", path: sub("Desktop")),
            Root(name: "Documents", path: sub("Documents")),
            Root(name: "Téléchargements", path: sub("Downloads")),
            Root(name: "Séquences", path: sub("Movies")),
            Root(name: "Bibliothèque", path: sub("Library")),
        ]
        roots = availableRoots
        let preferred = preferences.spaceStart.path
        let initial = availableRoots.first { $0.path == preferred } ?? availableRoots[0]
        root = initial
        stack = [initial.path]
        volumeNotifications = Publishers.MergeMany([
            volumeEvents.publisher(for: NSWorkspace.didMountNotification),
            volumeEvents.publisher(for: NSWorkspace.didUnmountNotification),
            volumeEvents.publisher(for: NSWorkspace.didRenameVolumeNotification)
        ]).receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.refreshVolumes()
        }

    }

    private static func startupDisk() -> Root {
        let name = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "Disque de démarrage"
        return Root(name: name + " · disque de démarrage", path: "/")
    }

    private static func withStartupDisk(_ roots: [Root]) -> [Root] {
        var seen: Set<String> = ["/"]
        return [roots.first { $0.path == "/" } ?? startupDisk()] + roots.filter { $0.path != "/" && seen.insert($0.path).inserted }
    }

    private static func mountedVolumes() -> [Root] {
        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey, .volumeIsLocalKey], options: [.skipHiddenVolumes]) ?? []
        return [startupDisk()] + mounted.filter {
            $0.path != "/" && !$0.path.hasPrefix("/System/Volumes/") && (try? $0.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) == true
        }.map { url in Root(name: (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? url.lastPathComponent, path: url.path) }
    }

    var locationChoices: [Root] { volumes.contains(root) ? volumes : volumes + [root] }

    /// Relit les montages avant l’ouverture du menu et après une notification de macOS.
    /// Aucune mesure n’est déclenchée par cette actualisation.
    func refreshVolumes() {
        let updated = Self.withStartupDisk(discoverVolumes())
        guard updated != volumes else { return }
        let removed = volumes.filter { old in old.path != "/" && !updated.contains { $0.path == old.path } }
        func wasRemoved(_ path: String) -> Bool {
            removed.contains { path == $0.path || path.hasPrefix($0.path + "/") }
        }
        let selectedWasRemoved = wasRemoved(root.path)
        let folders = roots.filter { candidate in
            !volumes.contains { $0.path == candidate.path } && !wasRemoved(candidate.path)
        }
        volumes = updated
        roots = updated + folders.filter { candidate in !updated.contains { $0.path == candidate.path } }
        if selectedWasRemoved {
            snapshots.removeAll()
            snapshotOrder.removeAll()
            setRoot(updated[0], measure: false)
            lastReport = nil
            statusMessage = "Le volume sélectionné a été éjecté. Choisissez un autre emplacement."
        } else if let current = roots.first(where: { $0.path == root.path }) {
            root = current
        }
    }

    var directDeleteLabel: String {
        directDelete ? "Supprimer définitivement" : "Déplacer vers la corbeille"
    }
    var currentPath: String { stack.last ?? root.path }
    var totalSize: UInt64 { children.reduce(0) { $0 + $1.size_bytes } }
    var maxChildSize: UInt64 { children.map(\.size_bytes).max() ?? 0 }
    var canGoUp: Bool { stack.count > 1 }

    /// Au moins un enfant n'a pas pu être lu en entier : les tailles affichées sont des minorants.
    var hasPartial: Bool { children.contains { !$0.measured } }
    /// Enfants non mesurés et rendus à 0 : rien à dessiner dans les bulles, mais à ne pas masquer.
    var unmeasuredEmpty: [SpaceChild] { children.filter { !$0.measured && $0.size_bytes == 0 } }

    /// Segments du fil d'ariane (nom affiché + chemin cible).
    var crumbs: [(name: String, path: String)] {
        stack.enumerated().map { idx, path in
            let name = idx == 0 ? root.name : URL(fileURLWithPath: path).lastPathComponent
            return (name, path)
        }
    }

    func setRoot(_ r: Root, measure: Bool = true) {
        guard roots.contains(r) else { return }
        stopMeasurement()
        root = r
        stack = [r.path]
        children = []
        hasMeasured = false
        lastMeasuredAt = nil
        statusMessage = nil
        selectedPath = nil
        highlightedPath = nil
        if measure { load() }
    }

    /// Un choix explicite de dossier ne lance jamais de mesure.
    func selectFolder(_ url: URL) {
        guard url.isFileURL else { return }
        let folder = url.resolvingSymlinksInPath().standardizedFileURL
        guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            statusMessage = "Ce dossier n’est plus accessible. Choisissez un autre emplacement."
            return
        }
        let choice = roots.first { $0.path == folder.path } ?? Root(name: folder.lastPathComponent.isEmpty ? "Disque de démarrage" : folder.lastPathComponent, path: folder.path)
        if !roots.contains(choice) { roots.append(choice) }
        setRoot(choice, measure: false)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choisir un dossier à explorer"
        panel.prompt = "Choisir ce dossier"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.selectFolder(url) }
        }
    }

    /// L’exploration élargie ne donne aucun nouveau droit de retrait hors du dossier personnel.
    func canRemove(_ child: SpaceChild) -> Bool {
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        let path = child.url.standardizedFileURL.path
        return path.hasPrefix(home + "/") && children.contains { $0.id == child.id }
    }

    var isDiskRoot: Bool { volumes.contains { $0.path == root.path } }

    func returnToStart() { setRoot(root, measure: false) }

    func select(_ child: SpaceChild) {
        guard children.contains(where: { $0.id == child.id }) else { return }
        selectedPath = child.id
    }

    /// Une sortie tardive de la liste ne doit pas effacer le survol acquis par la carte.
    func highlight(_ path: String?, from source: HoverSource) {
        if let path {
            guard children.contains(where: { $0.id == path }) else { return }
            hoverSource = source
            if highlightedPath != path { highlightedPath = path }
        } else if hoverSource == source {
            hoverSource = nil
            if highlightedPath != nil { highlightedPath = nil }
        }
    }

    func open(_ child: SpaceChild) {
        guard children.contains(where: { $0.id == child.id && $0.is_dir }) else { return }
        stack.append(child.path)
        restoreOrMeasure()
    }

    func goTo(path: String) {
        guard let idx = stack.firstIndex(of: path), idx < stack.count - 1 else { return }
        stack.removeSubrange((idx + 1)...)
        restoreOrMeasure()
    }

    func goUp() {
        guard canGoUp else { return }
        stack.removeLast()
        restoreOrMeasure()
    }

    /// Ignore aussi les réponses tardives d’une tâche qui ne pourrait pas s’arrêter immédiatement.
    private func stopMeasurement() {
        measureTask?.cancel()
        measureTask = nil
        isLoading = false
    }

    func cancelMeasurement() {
        guard isLoading else { return }
        stopMeasurement()
        children = []
        hasMeasured = false
        lastMeasuredAt = nil
        stack = [root.path]
        statusMessage = "Mesure interrompue. Vous pouvez choisir un dossier et relancer."
    }

    private func restoreOrMeasure() {
        stopMeasurement()
        selectedPath = nil
        highlightedPath = nil
        statusMessage = nil
        lastReport = nil
        if let snapshot = snapshots[currentPath] {
            children = snapshot.children
            lastMeasuredAt = snapshot.date
            hasMeasured = true
        } else {
            measureCurrent()
        }
    }

    private func remember(_ children: [SpaceChild], path: String, date: Date) {
        snapshots[path] = Snapshot(children: children, date: date)
        snapshotOrder.removeAll { $0 == path }
        snapshotOrder.append(path)
        if snapshotOrder.count > 12 {
            let oldest = snapshotOrder.removeFirst()
            snapshots.removeValue(forKey: oldest)
        }
    }

    func revealInFinder(_ child: SpaceChild) {
        NSWorkspace.shared.activateFileViewerSelecting([child.url])
    }

    /// Mesure le niveau courant.
    func load(keepReport: Bool = false) {
        // Une actualisation ou un retrait invalide aussi les vues parentes conservées.
        snapshots.removeAll()
        snapshotOrder.removeAll()
        measureCurrent(keepReport: keepReport)
    }

    private func measureCurrent(keepReport: Bool = false) {
        isLoading = true
        hasMeasured = false
        lastMeasuredAt = nil
        selectedPath = nil
        highlightedPath = nil
        statusMessage = nil
        if !keepReport {
            lastReport = nil
            // Navigation : la liste et le total affichés étaient ceux d'un autre dossier. Le
            // recalcul après un nettoyage (keepReport) garde en revanche la liste visible.
            children = []
        }
        let path = currentPath
        measureTask?.cancel()
        let task = EngineTask()
        measureTask = task
        liveEntries = 0
        liveBytes = 0
        Task { @MainActor in
            while task === self.measureTask && self.isLoading {
                let p = task.progress
                self.liveEntries = p.entries
                self.liveBytes = p.bytes
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        let measure = measureDirectory
        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · espace disque")
            defer { PowerAssertion.end(token) }
            let result: Result<[SpaceChild], Error>
            do {
                result = .success(try measure(path, task))
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                // Ignore un résultat périmé (mesure annulée ou remplacée par une navigation).
                guard path == self.currentPath, task === self.measureTask else { return }
                switch result {
                case .success(let found):
                    self.children = found
                    let date = Date()
                    self.lastMeasuredAt = date
                    self.hasMeasured = true
                    self.remember(found, path: path, date: date)
                case .failure(let err):
                    self.children = []
                    self.statusMessage = err.localizedDescription
                }
                self.isLoading = false
            }
        }
    }

    /// Déplace un élément vers la corbeille (ou le supprime), confiné à la racine d'exploration
    /// et re-validé par les gardes. Rafraîchit le niveau courant ensuite.
    func trash(_ child: SpaceChild, directOverride: Bool? = nil) {
        guard canRemove(child) else {
            statusMessage = "Cet emplacement est disponible en lecture seule dans MacCare."
            return
        }
        let scope = root.path
        let target = child.path
        let direct = directOverride ?? directDelete
        statusMessage = nil

        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · espace disque")
            defer { PowerAssertion.end(token) }

            let outcome: Result<RemovalReport, Error> = {
                var report = RemovalReport(direct: direct)
                do {
                    // Recalcule l'identité (device, inode) juste avant retrait.
                    let items = try Engine.inspectPaths([target], category: "space")
                    guard let item = items.first else {
                        report.failed.append((target, "élément introuvable"))
                        return .success(report)
                    }
                    let input = PlanInput(scope_root: scope,
                                          items: [PlanItem(path: item.path, identity: item.identity)])
                    if direct {
                        for r in try Engine.executeRemoval(input) {
                            if r.removed { report.removed += 1 }
                            else if !r.allowed { report.refused.append((r.path, r.refusal ?? "refusé")) }
                            else if let e = r.error { report.failed.append((r.path, e)) }
                        }
                    } else {
                        let decisions = try Engine.planRemoval(input)
                        let allowed = Set(decisions.filter(\.allowed).map(\.path))
                        for d in decisions where !d.allowed {
                            report.refused.append((d.path, d.refusal ?? "refusé"))
                        }
                        if allowed.contains(item.path) {
                            do {
                                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                                report.removed += 1
                            } catch {
                                report.failed.append((item.path, error.localizedDescription))
                            }
                        }
                    }
                    return .success(report)
                } catch {
                    return .failure(error)
                }
            }()

            await MainActor.run {
                switch outcome {
                case .success(let report):
                    self.lastReport = report
                    self.load(keepReport: true)
                case .failure(let err):
                    self.statusMessage = err.localizedDescription
                }
            }
        }
    }
}


extension SpaceChild {
    /// Taille à afficher : un enfant partiellement lu donne un minorant (« ≥ X »), jamais un « 0 »
    /// trompeur ; un enfant jamais lu est dit « non mesuré ».
    var sizeLabel: String {
        if measured { return humanSize(size_bytes) }
        return size_bytes == 0 ? "non mesuré" : "≥ " + humanSize(size_bytes)
    }
}
