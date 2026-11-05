import Foundation
import AppKit
import CoreServices
import Darwin

/// État d'une autorisation système.
enum PermissionState: Equatable {
    case unknown          // pas encore vérifié
    case notDetermined    // jamais demandé
    case granted
    case denied
}

/// Détection de l'« Accès complet au disque » de macOS.
///
/// macOS n'expose aucune API pour le demander : on le détecte en tentant d'ouvrir un fichier que
/// seule cette autorisation rend lisible. Le refus arrive en `EPERM`/`EACCES`.
enum FullDiskAccess {
    /// Fichiers-sondes lisibles uniquement avec l'Accès complet au disque.
    private static var probes: [String] {
        let home = NSHomeDirectory()
        return [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            home + "/Library/Safari/Bookmarks.plist",
        ]
    }

    /// `true` si une sonde est lisible, `false` si une sonde est refusée et aucune lisible,
    /// `nil` si aucune sonde n'existe (on ne peut pas conclure).
    private static func probe() -> Bool? {
        var denied = false
        for path in probes {
            let fd = open(path, O_RDONLY)
            if fd >= 0 {
                close(fd)
                return true
            }
            if errno == EPERM || errno == EACCES { denied = true }
        }
        return denied ? false : nil
    }

    private final class Box: @unchecked Sendable { var value: Bool? }

    /// Vérifie l'autorisation avec un délai maximal ; seul un accès confirmé vaut autorisation.
    static func isGranted(timeout: TimeInterval = 2.0) -> Bool {
        state(timeout: timeout) == .granted
    }

    static func state(timeout: TimeInterval = 2.0) -> PermissionState {
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            box.value = probe()
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut { return .unknown }
        return permissionState(for: box.value)
    }

    /// Une sonde absente ou indécidable ne prouve jamais qu'une autorisation est accordée.
    static func permissionState(for probe: Bool?) -> PermissionState {
        switch probe {
        case true: return .granted
        case false: return .denied
        case nil: return .unknown
        }
    }
}

/// Autorisation d'Automatisation vers System Events (lecture des éléments d'ouverture de session).
/// Contrairement à l'Accès complet au disque, macOS permet de la demander depuis l'app.
enum AutomationAccess {
    private static let systemEvents = "com.apple.systemevents"

    /// L'API de permission exige que la cible tourne : System Events est un petit démon, sans fenêtre.
    private static func ensureSystemEventsRunning() {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: systemEvents).isEmpty else { return }
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/System Events.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in done.signal() }
        _ = done.wait(timeout: .now() + 3)
    }

    /// `ask == false` : ne montre jamais de fenêtre. `ask == true` : peut afficher la fenêtre
    /// système et bloque jusqu'à la réponse (à appeler hors du thread principal).
    static func state(ask: Bool) -> PermissionState {
        ensureSystemEventsRunning()
        let target = NSAppleEventDescriptor(bundleIdentifier: systemEvents)
        guard let desc = target.aeDesc else { return .unknown }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        switch status {
        case 0: return .granted
        case -1744: return .notDetermined   // errAEEventWouldRequireUserConsent
        case -1743: return .denied          // errAEEventNotPermitted
        default: return .unknown
        }
    }
}

/// État des autorisations système et du parcours de premier lancement.
@MainActor
final class PermissionsModel: ObservableObject {
    enum Keys { static let firstRunCompleted = "firstRunCompleted" }

    @Published private(set) var fullDisk: PermissionState = .unknown
    @Published private(set) var automation: PermissionState = .unknown
    @Published private(set) var requestingAutomation = false
    /// Enregistré : le parcours de bienvenue ne se rejoue pas une fois terminé.
    @Published private(set) var firstRunCompleted: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        firstRunCompleted = defaults.bool(forKey: Keys.firstRunCompleted)
    }

    var needsOnboarding: Bool { !firstRunCompleted }

    var allGranted: Bool { fullDisk == .granted && automation == .granted }

    /// Autorisations encore manquantes, pour le rappel du tableau de bord.
    var missing: [String] {
        var items: [String] = []
        if fullDisk != .granted { items.append("Accès complet au disque") }
        if automation != .granted { items.append("Automatisation (System Events)") }
        return items
    }

    var showBanner: Bool { firstRunCompleted && !missing.isEmpty }

    /// Revérifie sans rien demander : au lancement et à chaque retour dans l'app.
    func recheck() {
        Task.detached(priority: .userInitiated) {
            let disk = FullDiskAccess.state()
            let auto = AutomationAccess.state(ask: false)
            await MainActor.run {
                self.fullDisk = disk
                self.automation = auto
            }
        }
    }

    /// Demande l'Automatisation : macOS affiche sa fenêtre d'autorisation.
    func requestAutomation() {
        guard !requestingAutomation else { return }
        requestingAutomation = true
        Task.detached(priority: .userInitiated) {
            let result = AutomationAccess.state(ask: true)
            await MainActor.run {
                self.automation = result
                self.requestingAutomation = false
            }
        }
    }

    func completeFirstRun() {
        firstRunCompleted = true
        defaults.set(true, forKey: Keys.firstRunCompleted)
    }

    func reopen() {
        firstRunCompleted = false
        defaults.set(false, forKey: Keys.firstRunCompleted)
    }

    /// Réglages Système > Confidentialité et sécurité > Accès complet au disque.
    func openFullDiskSettings() {
        openSettings("Privacy_AllFiles")
    }

    /// Réglages Système > Confidentialité et sécurité > Automatisation.
    func openAutomationSettings() {
        openSettings("Privacy_Automation")
    }

    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Montre MacCare dans le Finder, pour le glisser dans la liste si elle ne l'affiche pas.
    func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    /// macOS n'applique l'autorisation qu'à un processus relancé : on ouvre une nouvelle instance puis on quitte.
    func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { app, error in
            guard app != nil, error == nil else { return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
