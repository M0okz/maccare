import Foundation
import SwiftUI

/// Gros fichiers : repère les plus gros fichiers du dossier personnel (hors ~/Library, entrées
/// cachées et contenu des apps/bibliothèques), filtrables par taille et par ancienneté.
///
/// Ce sont des documents de l'utilisateur : rien n'est coché d'office, et la sélection part
/// **toujours à la corbeille**, même si la suppression directe est activée ailleurs. Chaque
/// fichier est re-validé par le moteur (identité inchangée, aucun lien symbolique, pas d'arbre
/// système) juste avant.
@MainActor
final class LargeFilesModel: ObservableObject {
    enum Stage: Equatable { case idle, scanning, results }

    /// Seuil de taille affiché (la recherche moteur part de 50 Mo ; le filtre est local).
    enum MinSize: UInt64, CaseIterable, Identifiable {
        case mb50 = 52_428_800, mb100 = 104_857_600, mb500 = 524_288_000, gb1 = 1_073_741_824
        var id: UInt64 { rawValue }
        var title: String {
            switch self {
            case .mb50: return "50 Mo"
            case .mb100: return "100 Mo"
            case .mb500: return "500 Mo"
            case .gb1: return "1 Go"
            }
        }
    }

    /// Ancienneté : depuis la dernière ouverture (Spotlight), à défaut la dernière modification.
    enum Age: Int, CaseIterable, Identifiable {
        case any = 0, months3 = 90, months6 = 182, year1 = 365
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .any: return "Tous"
            case .months3: return "> 3 mois"
            case .months6: return "> 6 mois"
            case .year1: return "> 1 an"
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case size = "Taille", age = "Ancienneté"
        var id: String { rawValue }
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var files: [LargeFile] = []
    /// Dernière ouverture connue de Spotlight, par chemin (absente si jamais ouvert ou non indexé).
    @Published private(set) var lastOpened: [String: Date] = [:]
    @Published var selection: Set<String> = []
    @Published var minSize: MinSize = .mb100
    @Published var age: Age = .any
    @Published var sort: Sort = .size
    @Published private(set) var liveEntries: UInt64 = 0
    @Published private(set) var liveBytes: UInt64 = 0
    @Published private(set) var isTrashing = false
    @Published private(set) var complete = true
    @Published var statusMessage: String?
    @Published private(set) var lastReport: RemovalReport?

    private var root = NSHomeDirectory()
    private var task: EngineTask?
    private var generation = 0

    /// Date retenue pour l'ancienneté d'un fichier.
    func lastUse(_ f: LargeFile) -> Date { lastOpened[f.path] ?? f.modifiedDate }

    /// Fichiers affichés, selon les filtres et le tri.
    var visible: [LargeFile] {
        let cutoff = Date().addingTimeInterval(-Double(age.rawValue) * 86_400)
        let kept = files.filter { $0.size_bytes >= minSize.rawValue && (age == .any || lastUse($0) < cutoff) }
        switch sort {
        case .size: return kept
        case .age: return kept.sorted { lastUse($0) < lastUse($1) }
        }
    }

    /// Seuls les fichiers visibles cochés partent : un filtre ne cache jamais une sélection active.
    var selectedFiles: [LargeFile] { visible.filter { selection.contains($0.path) } }
    var selectedSize: UInt64 { selectedFiles.reduce(0) { $0 + $1.size_bytes } }
    var visibleSize: UInt64 { visible.reduce(0) { $0 + $1.size_bytes } }

    func applyDefaultFilters(_ preferences: FileStoragePreferences = FileStoragePreferences()) {
        minSize = preferences.minSize
        age = preferences.age
    }

    // MARK: Recherche

    func scan(at location: URL? = nil) {
        let scanRoot = location?.standardizedFileURL.path ?? root
        task?.cancel()
        let task = EngineTask()
        self.task = task
        generation += 1
        let gen = generation

        stage = .scanning
        files = []
        lastOpened = [:]
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
            let token = PowerAssertion.beginUserActivity("MacCare · gros fichiers")
            defer { PowerAssertion.end(token) }
            let result: Result<LargeFilesResponse, Error>
            do {
                result = .success(try Engine.findLargeFiles(minBytes: MinSize.mb50.rawValue, root: scanRoot, task: task))
            } catch {
                result = .failure(error)
            }
            // Dernière ouverture selon Spotlight, hors du thread principal.
            var opened: [String: Date] = [:]
            if case .success(let r) = result {
                for f in r.files ?? [] {
                    if let d = NSMetadataItem(url: f.url)?.value(forAttribute: "kMDItemLastUsedDate") as? Date {
                        opened[f.path] = d
                    }
                }
            }
            let lastUsed = opened
            await MainActor.run {
                guard self.generation == gen else { return }
                switch result {
                case .success(let r):
                    self.root = r.root ?? self.root
                    self.files = r.files ?? []
                    self.lastOpened = lastUsed
                    self.complete = r.complete ?? true
                    self.statusMessage = self.complete ? nil : "Recherche incomplète : un dossier n'a pas répondu à temps."
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
        files = []; lastOpened = [:]; selection = []
        lastReport = nil; statusMessage = nil
        liveEntries = 0; liveBytes = 0
    }

    func cancel() {
        guard stage == .scanning else { return }
        task?.cancel()
    }

    // MARK: Sélection

    func toggle(_ f: LargeFile) {
        if selection.contains(f.path) { selection.remove(f.path) } else { selection.insert(f.path) }
    }
    func selectNone() { selection = [] }

    // MARK: Corbeille

    /// Met la sélection à la corbeille après validation par le moteur. Jamais de suppression
    /// directe ici. Les fichiers partis sont retirés de la liste (pas de nouvelle recherche).
    func trashSelected() {
        let chosen = selectedFiles
        guard !chosen.isEmpty else { return }
        isTrashing = true
        statusMessage = nil
        let root = self.root

        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · corbeille")
            defer { PowerAssertion.end(token) }
            var report = RemovalReport(direct: false)
            var gone: Set<String> = []
            var failure: String?
            do {
                let decisions = try Engine.planUserFiles(root: root, files: chosen)
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
                self.files.removeAll { removed.contains($0.path) }
                self.selection.subtract(removed)
                self.lastReport = message == nil ? final : nil
                self.statusMessage = message
                self.isTrashing = false
            }
        }
    }
}
