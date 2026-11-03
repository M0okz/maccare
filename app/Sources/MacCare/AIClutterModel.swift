import AppKit
import Foundation

@MainActor
final class AIClutterModel: ObservableObject {
    @Published private(set) var items: [ScanItem] = []
    @Published private(set) var locations: [AIClutterLocation] = []
    @Published var selection: Set<String> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published private(set) var hasScanned = false
    @Published private(set) var failed = false
    @Published private(set) var message: String?
    @Published private(set) var lastReport: RemovalReport?

    private let home: URL
    private let inspect: @Sendable ([String]) throws -> [ScanItem]
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         inspect: @escaping @Sendable ([String]) throws -> [ScanItem] = { try Engine.inspectPaths($0, category: "aiClutter") }) {
        self.home = home; self.inspect = inspect
    }
    var busy: Bool { isScanning || isCleaning }
    var selectedItems: [ScanItem] { items.filter { selection.contains($0.id) } }
    var selectedSize: UInt64 { selectedItems.reduce(0) { $0 + $1.size_bytes } }
    func location(for item: ScanItem) -> AIClutterLocation? { locations.first { $0.path == item.path } }

    func scan() {
        guard !busy else { return }
        isScanning = true; failed = false; message = nil; selection = []
        let home = home, inspect = inspect
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                let locations = AIClutterCatalog.locations(home: home)
                let exclusions = UserDefaults.standard.stringArray(forKey: "userExclusions") ?? []
                let paths = locations.map(\.path).filter { path in
                    !exclusions.contains { path == $0 || path.hasPrefix($0 + "/") }
                }
                return (locations, Result { try inspect(paths) })
            }.value
            locations = result.0
            switch result.1 {
            case .success(let found):
                let allowed = Set(locations.map(\.path))
                items = found.filter { $0.size_bytes > 0 && allowed.contains($0.path) }.sorted { $0.size_bytes > $1.size_bytes }
            case .failure(let error): items = []; failed = true; message = error.localizedDescription
            }
            isScanning = false; hasScanned = true
        }
    }

    /// Toujours récupérable dans la corbeille, même si la suppression directe est activée ailleurs.
    func trashSelected() {
        let chosen = selectedItems
        guard !busy && !chosen.isEmpty else { return }
        let apps = Set(chosen.compactMap { location(for: $0)?.application })
        let identifiers = ["Codex": "com.openai.codex", "Claude": "com.anthropic.claudefordesktop",
                           "ChatGPT": "com.openai.chat", "Cursor": "com.todesktop.230313mzl4w4u92",
                           "LM Studio": "ai.elementlabs.lmstudio"]
        let running = apps.filter { name in
            guard let identifier = identifiers[name] else { return false }
            return !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty
        }
        guard running.isEmpty else { message = "Quittez d’abord : \(running.sorted().joined(separator: ", "))."; return }
        isCleaning = true; message = nil
        let home = home
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                var report = RemovalReport(direct: false)
                let allowedPaths = Set(AIClutterCatalog.locations(home: home).map(\.path))
                let exclusions = UserDefaults.standard.stringArray(forKey: "userExclusions") ?? []
                // Les serveurs CLI de modèles peuvent continuer à tourner après fermeture de l'app.
                if apps.contains("Ollama"), SystemTools.run("/usr/bin/pgrep", ["-x", "ollama"]).ok {
                    report.refused = chosen.map { ($0.path, "Arrêtez le service Ollama avant de retirer ses modèles.") }
                    return report
                }
                for item in chosen {
                    do {
                        guard allowedPaths.contains(item.path), !exclusions.contains(where: { item.path == $0 || item.path.hasPrefix($0 + "/") }) else {
                            report.refused.append((item.path, "Emplacement hors du catalogue IA")); continue
                        }
                        // Revalidation par élément juste avant son déplacement : identité, liens et périmètre.
                        let input = PlanInput(scope_root: home.path, items: [.init(path: item.path, identity: item.identity)])
                        guard let decision = try Engine.planRemoval(input).first, decision.allowed else {
                            report.refused.append((item.path, "Le contrôle de sûreté refuse cet emplacement")); continue
                        }
                        try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                        report.removed += 1
                    } catch { report.failed.append((item.path, error.localizedDescription)) }
                }
                return report
            }.value
            lastReport = report; isCleaning = false
            scan()
        }
    }
}
