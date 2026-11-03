import Foundation
import SwiftUI

/// Doublons : fichiers au contenu identique dans le dossier personnel (hors ~/Library, entrées
/// cachées, contenu des apps et projets de code).
///
/// Dans chaque groupe, un exemplaire est **conservé** : par défaut le plus ancien, modifiable, et
/// jamais cochable. Rien n'est coché d'office. La sélection part **toujours à la corbeille**, après
/// que le moteur a vérifié que l'exemplaire conservé est présent et identique octet par octet.
@MainActor
final class DuplicatesModel: ObservableObject {
    enum Stage: Equatable { case idle, scanning, results }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var groups: [DupGroup] = []
    /// Exemplaire conservé, par groupe (identifiant de groupe → chemin).
    @Published private(set) var kept: [String: String] = [:]
    /// Chemins cochés pour la corbeille (jamais un exemplaire conservé).
    @Published private(set) var selection: Set<String> = []
    @Published private(set) var liveEntries: UInt64 = 0
    @Published private(set) var liveBytes: UInt64 = 0
    @Published private(set) var isTrashing = false
    @Published var statusMessage: String?
    @Published private(set) var lastReport: RemovalReport?

    private var root = NSHomeDirectory()
    private var task: EngineTask?
    private var generation = 0

    var reclaimable: UInt64 { groups.reduce(0) { $0 + $1.reclaimable } }
    var selectedFiles: [DupFile] { groups.flatMap(\.files).filter { selection.contains($0.path) } }
    var selectedSize: UInt64 { selectedFiles.reduce(0) { $0 + $1.size_bytes } }

    func keptPath(_ g: DupGroup) -> String? { kept[g.id] ?? g.files.first?.path }
    func isKept(_ f: DupFile, in g: DupGroup) -> Bool { keptPath(g) == f.path }

    // MARK: Recherche

    func scan(at location: URL? = nil) {
        let scanRoot = location?.standardizedFileURL.path ?? root
        task?.cancel()
        let task = EngineTask()
        self.task = task
        generation += 1
        let gen = generation

        stage = .scanning
        groups = []
        kept = [:]
        selection = []
        statusMessage = nil
        lastReport = nil
        liveEntries = 0
        liveBytes = 0

        Task { @MainActor in
            while self.generation == gen && self.stage == .scanning {
                let p = task.progress
                self.liveEntries = p.entries
                self.liveBytes = p.bytes
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · doublons")
            defer { PowerAssertion.end(token) }
            let result: Result<DuplicatesResponse, Error>
            do {
                result = .success(try Engine.findDuplicates(root: scanRoot, task: task))
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                guard self.generation == gen else { return }
                switch result {
                case .success(let r):
                    self.root = r.root ?? self.root
                    self.groups = r.groups ?? []
                    self.statusMessage = (r.complete ?? true) ? nil : "Recherche incomplète : un dossier n'a pas répondu à temps."
                    self.stage = .results
                case .failure(Engine.EngineError.cancelled):
                    self.statusMessage = "Recherche interrompue."
                    self.stage = .idle
                case .failure(let err):
                    self.statusMessage = err.localizedDescription
                    self.stage = .idle
                }
            }
        }
    }

    /// Un changement de dossier ne doit pas présenter les résultats du dossier précédent.
    func clearResults() {
        guard !isTrashing else { return }
        task?.cancel(); generation += 1
        stage = .idle
        groups = []; kept = [:]; selection = []
        lastReport = nil; statusMessage = nil
        liveEntries = 0; liveBytes = 0
    }

    func cancel() {
        guard stage == .scanning else { return }
        task?.cancel()
    }

    // MARK: Sélection

    /// Coche ou décoche une copie. L'exemplaire conservé ne se coche jamais.
    func toggle(_ f: DupFile, in g: DupGroup) {
        guard !isKept(f, in: g) else { return }
        if selection.contains(f.path) { selection.remove(f.path) } else { selection.insert(f.path) }
    }

    /// Fait de `f` l'exemplaire conservé du groupe (et le retire de la sélection).
    func keep(_ f: DupFile, in g: DupGroup) {
        kept[g.id] = f.path
        selection.remove(f.path)
    }

    /// Coche toutes les copies d'un groupe, sauf l'exemplaire conservé.
    func selectCopies(in g: DupGroup) {
        for f in g.files where !isKept(f, in: g) { selection.insert(f.path) }
    }

    func selectAllCopies() { groups.forEach(selectCopies(in:)) }
    func selectNone() { selection = [] }
    func retainSelection(in paths: Set<String>) { selection.formIntersection(paths) }

    // MARK: Corbeille

    func trashSelected() {
        let plan = groups.compactMap { g -> (DupGroup, DupFile, [DupFile])? in
            guard let keepPath = keptPath(g), let keep = g.files.first(where: { $0.path == keepPath }) else { return nil }
            let remove = g.files.filter { selection.contains($0.path) && $0.path != keepPath }
            return remove.isEmpty ? nil : (g, keep, remove)
        }
        guard !plan.isEmpty else { return }
        isTrashing = true
        statusMessage = nil
        let input = DuplicatesPlanInput(
            root: root,
            groups: plan.map { _, keep, remove in
                DuplicatesPlanGroup(
                    keep: PlanItem(path: keep.path, identity: keep.identity),
                    remove: remove.map { PlanItem(path: $0.path, identity: $0.identity) }
                )
            }
        )
        let chosen = plan.flatMap(\.2)

        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · corbeille")
            defer { PowerAssertion.end(token) }
            var report = RemovalReport(direct: false)
            var gone: Set<String> = []
            var failure: String?
            do {
                // Le moteur relit les contenus pour les comparer : hors du thread principal.
                let decisions = try Engine.planDuplicates(input)
                let allowed = Set(decisions.filter(\.allowed).map(\.path))
                for d in decisions where !d.allowed {
                    report.refused.append((d.path, d.refusal ?? "refusé"))
                }
                for f in chosen where allowed.contains(f.path) {
                    do {
                        try FileManager.default.trashItem(at: f.url, resultingItemURL: nil)
                        report.removed += 1
                        gone.insert(f.path)
                    } catch {
                        report.failed.append((f.path, error.localizedDescription))
                    }
                }
            } catch {
                failure = error.localizedDescription
            }
            let final = report, removed = gone, message = failure
            await MainActor.run {
                // Les copies parties quittent leur groupe ; un groupe d'un seul fichier disparaît.
                self.groups = self.groups.compactMap { g in
                    var g = g
                    g.files.removeAll { removed.contains($0.path) }
                    return g.files.count > 1 ? g : nil
                }
                self.selection.subtract(removed)
                self.lastReport = message == nil ? final : nil
                self.statusMessage = message
                self.isTrashing = false
            }
        }
    }
}
