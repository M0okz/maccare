import Foundation
import SwiftUI

/// Corbeilles : la corbeille du dossier personnel et celles des volumes montés.
///
/// Vider est **définitif** : rien n'est coché d'office, et le vidage passe toujours par une
/// confirmation avec le total exact (voir `TrashView`). Le moteur n'accepte que les corbeilles
/// qu'il repère lui-même, ne suit aucun lien, ne change pas de volume et ne force aucun verrou.
@MainActor
final class TrashModel: ObservableObject {
    @Published private(set) var bins: [TrashBin] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isEmptying = false
    @Published private(set) var hasLoaded = false
    @Published var selection: Set<String> = []
    @Published var statusMessage: String?
    /// Compte rendu du dernier vidage.
    @Published private(set) var lastSummary: String?
    @Published private(set) var lastNeedsAttention = false

    private var task: EngineTask?

    var selectedBins: [TrashBin] { bins.filter { selection.contains($0.path) && $0.readable } }
    var selectedSize: UInt64 { selectedBins.reduce(0) { $0 + $1.size_bytes } }
    var selectedItems: Int { selectedBins.reduce(0) { $0 + $1.items } }
    var totalSize: UInt64 { bins.filter(\.readable).reduce(0) { $0 + $1.size_bytes } }
    var hasUnreadable: Bool { bins.contains { !$0.readable } }

    func load() {
        task?.cancel()
        let task = EngineTask()
        self.task = task
        isLoading = true
        statusMessage = nil
        Task.detached(priority: .userInitiated) {
            let result: Result<[TrashBin], Error>
            do { result = .success(try Engine.listTrashes(task: task)) } catch { result = .failure(error) }
            await MainActor.run {
                guard task === self.task else { return }
                switch result {
                case .success(let found):
                    self.bins = found
                    // Une corbeille qui a disparu ou est devenue illisible sort de la sélection.
                    self.selection.formIntersection(found.filter(\.readable).map(\.path))
                case .failure(Engine.EngineError.cancelled):
                    break
                case .failure(let err):
                    self.statusMessage = err.localizedDescription
                }
                self.isLoading = false
                self.hasLoaded = true
            }
        }
    }

    func toggle(_ b: TrashBin) {
        guard b.readable, b.items > 0 else { return }
        if selection.contains(b.path) { selection.remove(b.path) } else { selection.insert(b.path) }
    }

    /// Vide **définitivement** la sélection. À n'appeler qu'après confirmation explicite.
    func emptySelected() {
        let chosen = selectedBins
        guard !chosen.isEmpty else { return }
        let task = EngineTask()
        self.task = task
        isEmptying = true
        statusMessage = nil
        lastSummary = nil

        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · vidage des corbeilles")
            defer { PowerAssertion.end(token) }
            let result: Result<TrashEmptyResponse, Error>
            do { result = .success(try Engine.emptyTrashes(chosen, task: task)) } catch { result = .failure(error) }
            await MainActor.run {
                switch result {
                case .success(let r):
                    let results = r.results ?? []
                    let removed = results.reduce(0) { $0 + $1.removed }
                    let freed = results.reduce(UInt64(0)) { $0 + $1.freed_bytes }
                    let failures = results.flatMap(\.failures)
                    let refused = results.compactMap(\.refusal)
                    if refused.contains("content-changed") && removed == 0 {
                        self.lastSummary = "La corbeille a changé depuis l'affichage : rien n'a été supprimé. Vérifiez la liste et recommencez."
                        self.lastNeedsAttention = true
                        break
                    }
                    var parts = ["\(removed) \(pl(removed, "élément")) \(pl(removed, "supprimé")) définitivement, \(humanSize(freed)) libérés"]
                    if !failures.isEmpty {
                        let reasons = Set(failures.map(\.error)).sorted().joined(separator: ", ")
                        parts.append("\(failures.count) non \(pl(failures.count, "supprimé")) (\(reasons))")
                    }
                    if refused.contains("content-changed") {
                        parts.append("une corbeille a changé depuis l'affichage et n'a pas été vidée")
                    } else if !refused.isEmpty {
                        parts.append("\(refused.count) \(pl(refused.count, "corbeille")) \(pl(refused.count, "refusée")) par sûreté")
                    }
                    if r.cancelled == true { parts.append("vidage interrompu") }
                    self.lastSummary = parts.joined(separator: " · ")
                    self.lastNeedsAttention = !failures.isEmpty || !refused.isEmpty
                case .failure(let err):
                    self.statusMessage = err.localizedDescription
                }
                self.selection = []
                self.isEmptying = false
                self.load()
            }
        }
    }

    /// Interrompt le vidage entre deux éléments.
    func cancelEmptying() {
        guard isEmptying else { return }
        task?.cancel()
    }
}
