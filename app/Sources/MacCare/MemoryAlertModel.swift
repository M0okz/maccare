import AppKit

@MainActor
final class MemoryAlertModel: ObservableObject {
    @Published private(set) var candidates: [MemoryAlertCandidate] = []
    @Published private(set) var pending: Set<TrayProcess.Identity> = []
    private var forceRequested: Set<TrayProcess.Identity> = []
    @Published private(set) var message: String?
    private var preview = false
    private let requestQuit: (MemoryAlertCandidate, Bool) -> String?

    init(requestQuit: ((MemoryAlertCandidate, Bool) -> String?)? = nil) {
        self.requestQuit = requestQuit ?? Self.quitApplication
    }

    func replace(_ candidates: [MemoryAlertCandidate], preview: Bool = false) {
        self.candidates = candidates
        self.preview = preview
        pending = []; forceRequested = []; message = nil
    }

    func quit(_ candidate: MemoryAlertCandidate) { perform([candidate], force: false) }
    func forceQuitDisplayed() { perform(candidates, force: true) }
    func clearMessage() { message = nil }
    var canForceQuit: Bool { candidates.contains { !forceRequested.contains($0.id) } }

    private func perform(_ targets: [MemoryAlertCandidate], force: Bool) {
        guard !preview else { message = "Aperçu : aucune application n’a été fermée."; return }
        var errors: [String] = []
        for candidate in targets where candidates.contains(where: { $0.id == candidate.id })
            && !(force ? forceRequested : pending).contains(candidate.id) {
            if let error = requestQuit(candidate, force) { errors.append(error) }
            else {
                pending.insert(candidate.id)
                if force { forceRequested.insert(candidate.id) }
            }
        }
        message = errors.isEmpty
            ? (force ? "Arrêt forcé demandé aux applications affichées." : "Fermeture demandée. L’application peut vous demander d’enregistrer vos documents.")
            : errors.joined(separator: "\n")
    }

    private static func quitApplication(_ candidate: MemoryAlertCandidate, force: Bool) -> String? {
        guard let info = TrayProcessSampler.info(candidate.id.pid),
              let app = MemoryAlertApplication.running(candidate.id.pid) else { return "\(candidate.name) n’est plus disponible." }
        let live = TrayProcess(id: TrayProcessSampler.identity(candidate.id.pid, info), name: candidate.process.name,
                               userID: info.pbsd.pbi_uid, memory: candidate.process.memory, cpuPercent: nil,
                               executable: app.executable)
        guard candidate.matches(live: live, application: app) else { return "\(candidate.name) a changé depuis le relevé. Aucune fermeture demandée." }
        let controller = TrayProcessController()
        controller.quit(live, force: force)
        return controller.pending.contains(live.id) ? nil : controller.message ?? "Impossible de quitter \(candidate.name)."
    }
}
