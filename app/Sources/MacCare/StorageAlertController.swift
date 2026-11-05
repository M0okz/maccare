import AppKit
import SwiftUI

/// Surveillance légère du disque de démarrage, tant que la barre des menus est active.
@MainActor
final class StorageAlertController: NSObject {
    private let policy = StorageAlertPolicy()
    private let anchor: () -> NSStatusBarButton?
    private let canPresent: () -> Bool
    private let openMacCare: () -> Void
    private let presenter = MenuBarAlertPresenter()
    var isVisible: Bool { presenter.isVisible }
    private var timer: Timer?
    private var previewObserver: NSObjectProtocol?
    private var suspended = false

    init(anchor: @escaping () -> NSStatusBarButton?, canPresent: @escaping () -> Bool,
         openMacCare: @escaping () -> Void) {
        self.anchor = anchor
        self.canPresent = canPresent
        self.openMacCare = openMacCare
        super.init()
        previewObserver = NotificationCenter.default.addObserver(
            forName: StorageAlertPolicy.previewNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.showPreview() }
        }
    }

    func syncAvailability() {
        guard anchor() != nil, policy.enabled, !suspended else {
            timer?.invalidate(); timer = nil
            dismiss()
            return
        }
        guard timer == nil else { return }
        let timer = Timer(fire: Date().addingTimeInterval(60), interval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func suspend() { suspended = true; syncAvailability() }
    func resume() { suspended = false; syncAvailability() }
    func dismiss() { presenter.dismiss() }

    private func check() {
        guard let volume = SpaceVolumeUsage.read(at: "/") else { return }
        let free = volume.total - min(volume.used, volume.total)
        if !StorageAlertPolicy.isLow(free: free, total: volume.total) { dismiss(); return }
        guard policy.shouldPresent(free: free, total: volume.total),
              !presenter.isVisible, canPresent(),
              UserDefaults.standard.bool(forKey: "firstRunCompleted"), !NSApp.isActive else { return }
        if present(volume: volume, preview: false) { policy.recordPresentation() }
    }

    private func showPreview() {
        guard !suspended, let actual = SpaceVolumeUsage.read(at: "/") else { return }
        // Données explicitement fictives ; aucun report ni délai réel n’est modifié par l’aperçu.
        let sample = SpaceVolumeUsage(name: actual.name, total: 500_000_000_000, used: 456_830_000_000)
        _ = present(volume: sample, preview: true)
    }

    @discardableResult
    private func present(volume: SpaceVolumeUsage, preview: Bool) -> Bool {
        let view = StorageAlertView(volume: volume,
            openMacCare: { [weak self] in
                self?.dismiss()
                self?.openMacCare()
            }, snooze: { [weak self] days in
                if !preview { self?.policy.snooze(days: days) }
                self?.dismiss()
            })
        return presenter.show(view, title: "MacCare — Espace disque faible", anchor: anchor())
    }

    func shutdown() {
        timer?.invalidate(); timer = nil
        dismiss()
        if let previewObserver { NotificationCenter.default.removeObserver(previewObserver) }
        previewObserver = nil
    }
}
