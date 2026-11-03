import SwiftUI
import AppIntents

@main
struct MacCareApp: App {
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState()
    @StateObject private var updater = AppUpdater()
    @AppStorage(MenuBarSetting.key) private var menuBarShown = MenuBarSetting.defaultValue

    init() {
        BatteryAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup("MacCare", id: Self.mainWindowID) {
            Group {
                #if DEBUG
                if TrayMetricPreview.isOverviewRequested {
                    MenuBarView(app: app, smart: app.smartScan, metricsStore: app.trayMetrics)
                } else if let preview = TrayMetricPreview.requestedKind {
                    TrayMetricPreview(kind: preview, metricsStore: app.trayMetrics)
                } else {
                    RootView(app: app)
                }
                #else
                RootView(app: app)
                #endif
            }
            .background(TraySceneLifecycle(app: app, delegate: delegate))
        }
        .windowStyle(.hiddenTitleBar)
        #if DEBUG
        .defaultSize(width: TrayMetricPreview.isOverviewRequested ? 540 : 1200, height: TrayMetricPreview.isOverviewRequested ? 820 : 720)
        #else
        .defaultSize(width: 1200, height: 720)
        #endif

        .commands {
            CommandGroup(after: .appInfo) {
                Button("Rechercher les mises à jour…", action: updater.checkForUpdates)
                    .disabled(!updater.canCheckForUpdates)
            }
            CommandGroup(after: .windowArrangement) {
                Button("Afficher le volet MacCare") { delegate.showTray() }
                    .disabled(!menuBarShown)
            }
        }

        HomeActivityWindow(kind: .memory, store: app.trayMetrics)
        HomeActivityWindow(kind: .cpu, store: app.trayMetrics)
        HomeActivityWindow(kind: .wifi, store: app.trayMetrics)

        Settings {
            SettingsView(permissions: app.permissions, model: app.review, systemClean: app.systemClean, updater: updater)
        }
        .windowResizability(.contentSize)
    }
}

/// Réglage « Afficher MacCare dans la barre des menus » (actif par défaut).
enum MenuBarSetting {
    static let key = "menuBarExtra"
    static let defaultValue = true
    static var enabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var tray: TrayPanelController?
    private var openSettingsAction: (() -> Void)?

    func configureOpenSettings(_ action: @escaping () -> Void) {
        openSettingsAction = action
        tray?.updateOpenSettings(action)
    }

    func configureTray(app: AppState, openMainWindow: @escaping () -> Void) {
        if let tray { tray.updateOpenMainWindow(openMainWindow) }
        else { tray = TrayPanelController(app: app, openMainWindow: openMainWindow, openSettings: openSettingsAction) }
    }

    func showTray() { tray?.show() }

    func applicationWillTerminate(_ notification: Notification) { tray?.shutdown() }

    /// Rouvre la fenêtre principale ; renseigné par l'app dès qu'une vue dispose de `openWindow`.
    static var openMainWindow: (() -> Void)?
    static var stopBatteryBeforeTermination: (() async -> Void)?
    private var terminationInProgress = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let stop = Self.stopBatteryBeforeTermination else { return .terminateNow }
        guard !terminationInProgress else { return .terminateLater }
        terminationInProgress = true
        Task { @MainActor in
            await stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Clic sur l'icône du Dock (ou réouverture depuis le Finder) sans fenêtre visible : avec la
    /// barre des menus, SwiftUI ne recrée pas la fenêtre de lui-même.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Self.openMainWindow?() }
        return true
    }

    /// Avec la barre des menus, fermer la fenêtre laisse MacCare actif (analyses planifiées) ;
    /// sans elle, l'app se ferme avec sa dernière fenêtre.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !MenuBarSetting.enabled
    }
}
