import Foundation
import SwiftUI

/// Un élément lancé au démarrage de session.
struct StartupItem: Identifiable, Hashable {
    enum Kind { case loginItem, launchAgent }
    let name: String
    let path: String
    let detail: String
    let kind: Kind
    var id: String { "\(kind)-\(path)-\(name)" }
    var url: URL { URL(fileURLWithPath: path) }
    var hasFile: Bool { !path.isEmpty && FileManager.default.fileExists(atPath: path) }
}

/// Ce qui s'ouvre au démarrage : éléments d'ouverture (login items, lecture seule : macOS n'offre
/// pas d'API pour couper ceux des autres apps, on ouvre les Réglages) et agents de lancement, lus
/// par le moteur. Un agent de l'utilisateur peut être **désactivé de façon réversible** (arrêté et
/// mis de côté par le moteur, réactivable ici) ; les agents du système restent en lecture seule.
@MainActor
final class StartupModel: ObservableObject {
    @Published private(set) var loginItems: [StartupItem] = []
    @Published private(set) var loginItemsError: String?
    @Published private(set) var loginItemsLoaded = false
    @Published private(set) var agents: [LaunchAgentInfo] = []
    /// Agent en cours de désactivation/réactivation.
    @Published private(set) var busyPath: String?
    /// Résultat de la dernière action sur un agent.
    @Published private(set) var lastAction: String?
    @Published private(set) var lastActionFailed = false
    @Published private(set) var isLoading = false
    @Published var statusMessage: String?
    @Published private(set) var hasLoaded = false

    var userAgents: [LaunchAgentInfo] { agents.filter { $0.scope == "user" } }
    var disabledAgents: [LaunchAgentInfo] { agents.filter { $0.scope == "disabled" } }
    var systemAgents: [LaunchAgentInfo] { agents.filter { $0.scope == "system" } }
    var orphanCount: Int { userAgents.filter(\.orphan).count }
    var total: Int { loginItems.count + agents.count }

    private var includeLoginItems = false

    func load(includeLoginItems: Bool = false) {
        guard !isLoading && busyPath == nil else { return }
        self.includeLoginItems = includeLoginItems
        isLoading = true
        loginItemsLoaded = false
        loginItemsError = nil
        statusMessage = nil
        Task.detached(priority: .userInitiated) {
            // Les agents de lancement se lisent sans autorisation.
            let agents: [LaunchAgentInfo]
            do { agents = try Engine.listAgents() }
            catch {
                await MainActor.run {
                    self.statusMessage = error.localizedDescription
                    self.agents = []
                    self.loginItems = []
                    self.isLoading = false
                    self.hasLoaded = true
                }
                return
            }
            await MainActor.run {
                self.agents = agents.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            }
            // Les éléments d’ouverture passent par System Events. La vue ne les demande
            // qu’après confirmation de l’autorisation existante, sans provoquer de demande implicite.
            let logins: [StartupItem]
            let loginError: String?
            do {
                logins = includeLoginItems ? try Self.readLoginItems() : []
                loginError = nil
            } catch {
                logins = []
                loginError = error.localizedDescription
            }
            await MainActor.run {
                self.loginItems = logins
                self.loginItemsError = loginError
                self.loginItemsLoaded = includeLoginItems && loginError == nil
                self.isLoading = false
                self.hasLoaded = true
            }
        }
    }

    /// Éléments d'ouverture via System Events (AppleScript).
    nonisolated static func readLoginItems() throws -> [StartupItem] {
        let osa = "/usr/bin/osascript"
        let names = SystemTools.run(osa, ["-e", "tell application \"System Events\" to get the name of every login item"])
        guard names.ok else {
            throw NSError(domain: "MacCare.Startup", code: Int(names.status), userInfo: [NSLocalizedDescriptionKey: "Impossible de lire les éléments d’ouverture. Vérifiez l’autorisation Automatisation, puis actualisez."])
        }
        let paths = SystemTools.run(osa, ["-e", "tell application \"System Events\" to get the path of every login item"])

        guard paths.ok else {
            throw NSError(domain: "MacCare.Startup", code: Int(paths.status), userInfo: [NSLocalizedDescriptionKey: "Impossible de lire les emplacements des éléments d’ouverture. Actualisez la liste."])
        }
        let nameList = split(names.stdout)
        let pathList = split(paths.stdout)
        var items: [StartupItem] = []
        for (i, n) in nameList.enumerated() where !n.isEmpty {
            let raw = i < pathList.count ? pathList[i] : ""
            // AppleScript renvoie la chaîne littérale « missing value » quand le chemin est inconnu.
            let p = raw == "missing value" ? "" : raw
            items.append(StartupItem(name: n, path: p, detail: p.isEmpty ? "Chemin indisponible" : p, kind: .loginItem))
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated private static func split(_ s: String) -> [String] {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Désactive un agent (après confirmation dans la vue) ou réactive un agent mis de côté.
    func toggle(_ agent: LaunchAgentInfo) {
        guard busyPath == nil && !isLoading else { return }
        let action = agent.scope == "disabled" ? "enable" : "disable"
        guard action == "enable" || agent.canDisable else { return }
        busyPath = agent.path
        lastAction = nil
        Task.detached(priority: .userInitiated) {
            let result: Result<String, Error>
            do { result = .success(try Engine.setAgent(action, agent)) } catch { result = .failure(error) }
            await MainActor.run {
                switch result {
                case .success:
                    self.lastAction = action == "disable"
                        ? "« \(agent.label) » désactivé. Réactivable à tout moment dans « Désactivés par MacCare »."
                        : "« \(agent.label) » réactivé."
                    self.lastActionFailed = false
                case .failure(let err):
                    self.lastAction = "« \(agent.label) » : \(Self.explain(err.localizedDescription))"
                    self.lastActionFailed = true
                }
                self.busyPath = nil
                self.load(includeLoginItems: self.includeLoginItems)
            }
        }
    }

    nonisolated static func explain(_ message: String) -> String {
        let codes = [
            "not-listed": "il n'existe plus à cet emplacement",
            "launchctl-unknown": "état du système illisible, rien n'a été changé ; réessayez",
            "apple": "agent Apple, non modifiable",
            "identity-changed": "il a changé depuis l'affichage, actualisez",
            "occupied": "un autre fichier occupe son emplacement d'origine",
            "symlink": "lien symbolique refusé",
            "outside-scope": "emplacement d'origine invalide",
        ]
        return codes.first { message.hasSuffix($0.key) }?.value ?? message
    }

    func reveal(_ agent: LaunchAgentInfo) {
        NSWorkspace.shared.activateFileViewerSelecting([agent.url])
    }

    func reveal(_ item: StartupItem) {
        guard item.hasFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Ouvre Réglages système > Général > Ouverture.
    func openLoginSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Filtres de présentation, sans action sur les éléments affichés.
enum StartupFilter: String, CaseIterable, Identifiable {
    case all, login, agents, disabled, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Tous les éléments"
        case .login: return "Apps à la connexion"
        case .agents: return "Agents de votre session"
        case .disabled: return "Désactivés par MacCare"
        case .system: return "Système · lecture seule"
        }
    }
    static func matches(_ query: String, values: [String]) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || values.contains { $0.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
