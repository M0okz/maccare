import AppKit
import SwiftUI

@MainActor
final class MemoryAlertController {
    private var policy = MemoryAlertPolicy()
    private let anchor: () -> NSStatusBarButton?
    private let canPresent: () -> Bool
    private let sampler = TrayProcessSampler()
    private let presenter = MenuBarAlertPresenter()
    private let model = MemoryAlertModel()
    private var timer: Timer?
    private var sampling: Task<Void, Never>?
    private var previewObserver: NSObjectProtocol?
    private var suspended = false
    private var previewShowing = false
    var isVisible: Bool { presenter.isVisible }

    init(anchor: @escaping () -> NSStatusBarButton?, canPresent: @escaping () -> Bool) {
        self.anchor = anchor; self.canPresent = canPresent
        previewObserver = NotificationCenter.default.addObserver(forName: MemoryAlertPolicy.previewNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showPreview() }
        }
    }

    func syncAvailability() {
        guard anchor() != nil, policy.enabled, !suspended else {
            timer?.invalidate(); timer = nil
            sampling?.cancel(); sampling = nil
            policy.resetObservation(); dismiss()
            return
        }
        guard timer == nil else { return }
        let timer = Timer(fire: Date().addingTimeInterval(60), interval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func suspend() { suspended = true; syncAvailability() }
    func resume() { suspended = false; syncAvailability() }
    func dismiss() { presenter.dismiss() }

    private func check() {
        if previewShowing && isVisible { return }
        previewShowing = false
        let pressure = MemoryPressureLevel.current()
        let sustained = policy.observe(pressure, uptime: ProcessInfo.processInfo.systemUptime)
        if pressure == .normal || pressure == nil { dismiss(); return }
        guard sustained, eligible, sampling == nil, policy.shouldPresent(),
              UserDefaults.standard.bool(forKey: "firstRunCompleted") else { return }
        let sampler = sampler
        sampling = Task { [weak self] in
            let processes = await sampler.sample()
            guard let self else { return }
            defer { self.sampling = nil }
            guard !Task.isCancelled, self.eligible, self.policy.shouldPresent(),
                  let pressure = MemoryPressureLevel.current(), pressure != .normal else { return }
            let apps = processes.filter { $0.canQuit && $0.memory >= 512_000_000 }
                .compactMap { MemoryAlertApplication.running($0.id.pid) }
            let candidates = MemoryAlertCandidate.ranked(processes: processes, applications: apps)
            guard !candidates.isEmpty else { return }
            self.model.replace(candidates)
            if self.present() { self.policy.recordPresentation() }
        }
    }

    private var eligible: Bool {
        !suspended && anchor() != nil && policy.enabled && canPresent() && !isVisible && !NSApp.isActive
    }

    private func showPreview() {
        guard !suspended else { return }
        let path = "/Applications/Helium.app"
        let process = TrayProcess(id: .init(pid: -1, startedSeconds: 0, startedMicroseconds: 0), name: "Helium",
                                  userID: getuid(), memory: 1_430_000_000, cpuPercent: nil,
                                  executable: path + "/Contents/MacOS/Helium")
        let application = MemoryAlertApplication(pid: -1, name: "Helium", bundleID: "preview.helium",
                                               bundlePath: path, executable: process.executable, isRegular: true)
        model.replace([MemoryAlertCandidate(process: process, application: application)], preview: true)
        previewShowing = true
        _ = present()
    }

    @discardableResult private func present() -> Bool {
        presenter.show(MemoryAlertView(model: model, snooze: { [weak self] days in
            self?.snooze(days: days)
        }), title: "MacCare — Consommation de mémoire élevée", anchor: anchor())
    }

    private func snooze(days: Int) {
        // Un aperçu est identifiable par ses PID impossibles ; il ne modifie jamais les rappels.
        if model.candidates.contains(where: { $0.id.pid > 0 }) { policy.snooze(days: days) }
        dismiss()
    }

    func shutdown() {
        timer?.invalidate(); timer = nil
        sampling?.cancel(); sampling = nil
        dismiss()
        if let previewObserver { NotificationCenter.default.removeObserver(previewObserver) }
        previewObserver = nil
    }
}
