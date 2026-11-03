import Combine
import Foundation
import Sparkle

/// Un seul contrôleur Sparkle pour les recherches manuelles et automatiques de MacCare.
@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
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
        guard AppUpdateConfiguration(info: bundle.infoDictionary ?? [:]) != nil else {
            unavailableReason = "Les mises à jour seront disponibles dans la version distribuée de MacCare."
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        do {
            try controller.updater.start()
            controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
            controller.updater.publisher(for: \.lastUpdateCheckDate).assign(to: &$lastCheckDate)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecksForUpdates)
        } catch {
            unavailableReason = "La recherche de mises à jour est indisponible : \(error.localizedDescription)"
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates, isAvailable else { return }
        controller?.checkForUpdates(nil)
    }
}
