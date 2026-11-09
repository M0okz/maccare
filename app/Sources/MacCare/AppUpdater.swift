import Combine
import Foundation
import Sparkle

/// Un seul contrôleur Sparkle pour les recherches manuelles et automatiques de MacCare.
@MainActor
final class AppUpdater: NSObject, ObservableObject, @MainActor SPUStandardUserDriverDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var availableVersion: String?
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var unavailableReason: String?
    @Published var automaticallyChecksForUpdates = false {
        didSet {
            guard let updater = controller?.updater,
                  updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }
    private var controller: SPUStandardUpdaterController?
    var isAvailable: Bool { controller != nil && unavailableReason == nil }

    init(bundle: Bundle = .main) {
        super.init()
        guard AppUpdateConfiguration(info: bundle.infoDictionary ?? [:]) != nil else {
            unavailableReason = "Les mises à jour seront disponibles dans la version distribuée de MacCare."
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        do {
            try controller.updater.start()
            controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
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
    }

    func standardUserDriverWillFinishUpdateSession() {
        // Respect the user's Later/Skip choice and remove reminders after an error.
        availableVersion = nil
    }

}
