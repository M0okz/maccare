import Combine
import Foundation
import Sparkle
import AppKit
import UserNotifications

/// Un seul contrôleur Sparkle pour les recherches manuelles et automatiques de MacCare.
@MainActor
final class AppUpdater: NSObject, ObservableObject, @MainActor SPUStandardUserDriverDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var availableVersion: String?
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var unavailableReason: String?
    @Published private(set) var notificationAuthorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var notificationError: String?
    @Published var automaticallyChecksForUpdates = false {
        didSet {
            if !automaticallyChecksForUpdates { updateNotifications.clear() }
            guard let updater = controller?.updater,
                  updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }
    private var controller: SPUStandardUpdaterController?
    private let updateNotifications: AppUpdateNotifications
    private var observations = Set<AnyCancellable>()
    private var pendingNotificationOpen = false
    private var backgroundUpdate: (version: String, build: String)?
    var isAvailable: Bool { controller != nil && unavailableReason == nil }

    init(bundle: Bundle = .main, notifications: AppUpdateNotifications? = nil) {
        updateNotifications = notifications ?? AppUpdateNotifications()
        super.init()
        guard AppUpdateConfiguration(info: bundle.infoDictionary ?? [:]) != nil else {
            unavailableReason = "Les mises à jour seront disponibles dans la version distribuée de MacCare."
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        NotificationCenter.default.publisher(for: .appUpdateNotificationSelected)
            .sink { [weak self] _ in
                Task { @MainActor in self?.showUpdateFromNotification() }
            }.store(in: &observations)
        do {
            try controller.updater.start()
            controller.updater.publisher(for: \.canCheckForUpdates).sink { [weak self] ready in
                guard let self else { return }
                self.canCheckForUpdates = ready
                if ready, self.pendingNotificationOpen {
                    self.pendingNotificationOpen = false
                    self.checkForUpdates()
                }
            }.store(in: &observations)
            controller.updater.publisher(for: \.lastUpdateCheckDate).assign(to: &$lastCheckDate)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecksForUpdates)
            // Sparkle permits an initial background check immediately after start.
            // Respect the user's automatic-check setting and keep its scheduler thereafter.
            if controller.updater.automaticallyChecksForUpdates {
                controller.updater.checkForUpdatesInBackground()
            }
        } catch {
            unavailableReason = "La recherche de mises à jour est indisponible : \(error.localizedDescription)"
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates, isAvailable else { return }
        controller?.checkForUpdates(nil)
    }

    /// A notification can reopen a closed main window or arrive during the initial check.
    func showUpdateFromNotification() {
        guard isAvailable else { return }
        updateNotifications.clear()
        DockVisibilityController.activateForWindow()
        AppDelegate.openMainWindow?()
        if canCheckForUpdates { checkForUpdates() }
        else { pendingNotificationOpen = true }
    }

    func refreshNotificationAuthorization() async {
        notificationAuthorization = await updateNotifications.authorizationStatus()
    }

    /// Called only by the notification controls in Settings.
    func requestUpdateNotificationPermission() async {
        notificationError = nil
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) }
        catch { notificationError = "Impossible d’activer les notifications. Vérifiez les réglages de notifications de macOS." }
        await refreshNotificationAuthorization()
        if automaticallyChecksForUpdates, let update = backgroundUpdate {
            await updateNotifications.announce(version: update.version, build: update.build)
        }
    }

    func clearUpdateNotification() { updateNotifications.clear() }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Critical releases retain Sparkle's immediate presentation.
        update.isCriticalUpdate
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        availableVersion = update.displayVersionString
        if automaticallyChecksForUpdates, !handleShowingUpdate, !state.userInitiated {
            backgroundUpdate = (update.displayVersionString, update.versionString)
            Task { @MainActor [weak self] in
                guard let self, self.automaticallyChecksForUpdates,
                      self.backgroundUpdate?.build == update.versionString else { return }
                await self.updateNotifications.announce(version: update.displayVersionString, build: update.versionString)
            }
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updateNotifications.clear()
    }

    func standardUserDriverWillFinishUpdateSession() {
        // Respect the user's Later/Skip choice and remove reminders after an error.
        availableVersion = nil
        backgroundUpdate = nil
        updateNotifications.clear()
    }

}
