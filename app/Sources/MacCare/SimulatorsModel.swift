import Foundation
import SwiftUI

/// Simulateurs Xcode et leurs runtimes (outils pour développeurs).
///
/// Supprimer un simulateur efface **définitivement** ses apps et données de test ; supprimer un
/// runtime rend inutilisables les simulateurs qui en dépendent. Rien n'est coché d'office, la
/// suppression passe par une confirmation, et le moteur ne passe que par `simctl` (localisé sans jamais proposer d'installer Xcode), sur
/// une liste qu'il relit lui-même (jamais un simulateur allumé).
@MainActor
final class SimulatorsModel: ObservableObject {
    @Published private(set) var simulators: [SimDevice] = []
    @Published private(set) var runtimes: [SimRuntimeInfo] = []
    @Published private(set) var xcodeInstalled = true
    @Published private(set) var isLoading = false
    @Published private(set) var isDeleting = false
    @Published private(set) var hasLoaded = false
    @Published var selectedSims: Set<String> = []
    @Published var selectedRuntimes: Set<String> = []
    @Published var statusMessage: String?
    @Published private(set) var lastSummary: String?
    @Published private(set) var lastNeedsAttention = false

    private var task: EngineTask?

    var chosenSims: [SimDevice] { simulators.filter { selectedSims.contains($0.udid) && !$0.isBooted } }
    var chosenRuntimes: [SimRuntimeInfo] { runtimes.filter { selectedRuntimes.contains($0.identifier) && $0.deletable } }
    var selectedSize: UInt64 {
        chosenSims.reduce(0) { $0 + $1.size_bytes } + chosenRuntimes.reduce(0) { $0 + $1.size_bytes }
    }
    var hasSelection: Bool { !chosenSims.isEmpty || !chosenRuntimes.isEmpty }
    var totalSize: UInt64 {
        simulators.reduce(0) { $0 + $1.size_bytes } + runtimes.reduce(0) { $0 + $1.size_bytes }
    }
    var unavailableCount: Int { simulators.filter { !$0.available && !$0.isBooted }.count }

    func load() {
        task?.cancel()
        let task = EngineTask()
        self.task = task
        isLoading = true
        statusMessage = nil
        Task.detached(priority: .userInitiated) {
            let result: Result<SimulatorsResponse, Error>
            do { result = .success(try Engine.listSimulators(task: task)) } catch { result = .failure(error) }
            await MainActor.run {
                guard task === self.task else { return }
                switch result {
                case .success(let r):
                    self.xcodeInstalled = r.xcode ?? false
                    self.simulators = r.simulators ?? []
                    self.runtimes = (r.runtimes ?? []).sorted { $0.size_bytes > $1.size_bytes }
                    self.selectedSims.formIntersection(self.simulators.map(\.udid))
                    self.selectedRuntimes.formIntersection(self.runtimes.map(\.identifier))
                    self.statusMessage = r.warnings?.first
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

    func toggle(_ s: SimDevice) {
        guard !s.isBooted else { return }
        if selectedSims.contains(s.udid) { selectedSims.remove(s.udid) } else { selectedSims.insert(s.udid) }
    }

    func toggle(_ r: SimRuntimeInfo) {
        guard r.deletable else { return }
        if selectedRuntimes.contains(r.identifier) { selectedRuntimes.remove(r.identifier) } else { selectedRuntimes.insert(r.identifier) }
    }

    /// Coche les simulateurs inutilisables (runtime absent) : ils ne peuvent plus démarrer.
    func selectUnavailable() {
        for s in simulators where !s.available && !s.isBooted { selectedSims.insert(s.udid) }
    }

    func selectNone() {
        selectedSims = []
        selectedRuntimes = []
    }

    /// Supprime **définitivement** la sélection. À n'appeler qu'après confirmation explicite.
    func deleteSelected() {
        let sims = chosenSims.map(\.udid)
        let rts = chosenRuntimes.map(\.identifier)
        guard !sims.isEmpty || !rts.isEmpty else { return }
        let task = EngineTask()
        self.task = task
        isDeleting = true
        lastSummary = nil
        statusMessage = nil
        let freedEstimate = selectedSize

        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · simulateurs")
            defer { PowerAssertion.end(token) }
            let result: Result<[SimDeleteResult], Error>
            do { result = .success(try Engine.deleteSimulators(sims, runtimes: rts, task: task)) } catch { result = .failure(error) }
            await MainActor.run {
                switch result {
                case .success(let results):
                    let removed = results.filter(\.removed).count
                    let failed = results.filter { !$0.removed }
                    var parts = ["\(removed) supprimé(s) définitivement"]
                    if failed.isEmpty { parts.append("environ \(humanSize(freedEstimate)) libérés") }
                    if !failed.isEmpty {
                        let reasons = Set(failed.compactMap(\.error).map(Self.explain)).sorted().joined(separator: ", ")
                        parts.append("\(failed.count) refusé(s) ou en échec (\(reasons))")
                    }
                    self.lastSummary = parts.joined(separator: " · ")
                    self.lastNeedsAttention = !failed.isEmpty
                case .failure(let err):
                    self.statusMessage = err.localizedDescription
                }
                self.selectNone()
                self.isDeleting = false
                self.load()
            }
        }
    }

    func cancel() { task?.cancel() }

    static func explain(_ code: String) -> String {
        switch code {
        case "booted": return "simulateur allumé"
        case "not-listed": return "n'existe plus"
        case "not-deletable": return "runtime protégé par le système"
        case "invalid-id": return "identifiant invalide"
        case "xcode-absent": return "Xcode n'est pas installé"
        default: return code
        }
    }
}
