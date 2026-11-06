import AppKit
import MacCareBattery
import SwiftUI

@MainActor
final class AdditionalAlertsController {
    private let battery: BatteryModel
    private let anchor: () -> NSStatusBarButton?
    private let canPresent: () -> Bool
    private let openBattery: () -> Void
    private let openCPU: () -> Void
    private let presenter = MenuBarAlertPresenter()
    private let sampler = TrayProcessSampler()
    private let processes = MemoryAlertModel()
    private var cpu = CPUAlertCondition()
    /// Lecture dédiée : le suivi de l’activité ne tourne que lorsqu’un écran l’affiche.
    private var cpuLoad = CPULoadCounter()
    private var detector = BatteryAlertDetector()
    private var pendingCompletion: BatteryCompletionAlert?
    private var visibleKind: AdditionalAlertKind?
    private var preview = false
    private var timer: Timer?
    private var previewObserver: NSObjectProtocol?
    private var sampling: Task<Void, Never>?
    private var suspended = false
    var isVisible: Bool { presenter.isVisible }

    init(battery: BatteryModel, anchor: @escaping () -> NSStatusBarButton?,
         canPresent: @escaping () -> Bool, openBattery: @escaping () -> Void, openCPU: @escaping () -> Void) {
        self.battery = battery; self.anchor = anchor; self.canPresent = canPresent
        self.openBattery = openBattery; self.openCPU = openCPU
        previewObserver = NotificationCenter.default.addObserver(forName: AdditionalAlertKind.previewNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?["kind"] as? String, let kind = AdditionalAlertKind(rawValue: raw) else { return }
            Task { @MainActor in self?.showPreview(kind) }
        }
    }

    func syncAvailability() {
        let enabled = AdditionalAlertKind.allCases.contains { AdditionalAlertReminder($0).enabled }
        guard !suspended, anchor() != nil, enabled else { stop(); return }
        if let visibleKind, !AdditionalAlertReminder(visibleKind).enabled, !preview { dismiss() }
        if !AdditionalAlertReminder(.cpu).enabled { cpu.reset(); cpuLoad.reset() }
        guard timer == nil else { return }
        _ = cpuLoad.read()
        let timer = Timer(fire: Date().addingTimeInterval(5), interval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func suspend() { suspended = true; stop() }
    func resume() { suspended = false; syncAvailability() }
    func dismiss() { presenter.dismiss(); visibleKind = nil; preview = false }
    private func stop() {
        timer?.invalidate(); timer = nil
        sampling?.cancel()
        cpu.reset(); cpuLoad.reset(); detector.reset(); pendingCompletion = nil
        dismiss()
    }

    private func observation() -> BatteryAlertObservation {
        .init(expected: battery.protectionExpectedForAlerts && battery.snapshot?.present != false,
              helperReady: battery.helperEnabled && !battery.helperUpdateRequired, status: battery.protection,
              cancellation: battery.alertCancellation, terminating: battery.isTerminating)
    }

    private func check() {
        let now = Date(), uptime = ProcessInfo.processInfo.systemUptime
        if AdditionalAlertReminder(.cpu).enabled { cpu.observe(fraction: cpuLoad.read()?.used, sampledAt: uptime) }
        if !battery.controlsBusy {
            let value = observation()
            if let completion = detector.observe(value, uptime: uptime, now: now) { pendingCompletion = completion }
            if !value.healthy || value.status?.snapshot.onAC != true ||
                (pendingCompletion != nil && value.status?.configuration?.limit != pendingCompletion?.target) { pendingCompletion = nil }
        }
        if let completion = pendingCompletion, now.timeIntervalSince(completion.createdAt) > 1800 { pendingCompletion = nil }
        if !isVisible { preview = false; visibleKind = nil }
        if !preview {
            if visibleKind == .protection && !detector.interrupted { dismiss() }
            if visibleKind == .cpu && (!cpu.sustained || !cpu.isFresh(at: uptime)) { dismiss() }
        }
        guard !isVisible, eligible else { return }
        if detector.interrupted, AdditionalAlertReminder(.protection).shouldPresent() {
            presentBattery(completion: nil, preview: false)
        } else if let completion = pendingCompletion, AdditionalAlertReminder(.cycle).shouldPresent() {
            presentBattery(completion: completion, preview: false)
            if visibleKind == .cycle { pendingCompletion = nil }
        } else if cpu.sustained, cpu.isFresh(at: uptime), sampling == nil, AdditionalAlertReminder(.cpu).shouldPresent() {
            sampleProcesses()
        }
    }

    private var eligible: Bool {
        !suspended && anchor() != nil && canPresent() && !NSApp.isActive && !battery.controlsBusy
            && UserDefaults.standard.bool(forKey: "firstRunCompleted")
    }

    private func sampleProcesses() {
        let sampler = sampler
        sampling = Task { [weak self] in
            _ = await sampler.sample()
            do { try await Task.sleep(for: .seconds(1)) } catch { self?.sampling = nil; return }
            let rows = await sampler.sample()
            guard let self else { return }
            defer { self.sampling = nil }
            guard !Task.isCancelled, self.eligible, !self.isVisible, self.cpu.sustained,
                  self.cpu.isFresh(at: ProcessInfo.processInfo.systemUptime), !self.detector.interrupted,
                  self.pendingCompletion == nil, AdditionalAlertReminder(.cpu).shouldPresent() else { return }
            let apps = rows.filter { $0.canQuit && ($0.cpuPercent ?? 0) >= 50 }
                .compactMap { MemoryAlertApplication.running($0.id.pid) }
            self.processes.replace(CPUAlertRanking.candidates(rows, applications: apps))
            self.presentCPU(preview: false)
        }
    }

    private func presentCPU(preview: Bool) {
        self.preview = preview
        let view = CPUAlertView(model: processes, fraction: preview ? 0.94 : cpu.fraction,
                                snooze: { [weak self] in self?.snooze(.cpu, days: $0) },
                                openActivity: { [weak self] in self?.dismiss(); self?.openCPU() })
        if presenter.show(view, title: "MacCare — CPU fortement sollicité", anchor: anchor()) {
            visibleKind = .cpu
            if !preview { AdditionalAlertReminder(.cpu).record() }
        }
    }

    private func presentBattery(completion: BatteryCompletionAlert?, preview: Bool) {
        let kind: AdditionalAlertKind = completion == nil ? .protection : .cycle
        self.preview = preview
        let view = BatteryStatusAlertView(completion: completion, limit: completion?.target ?? battery.configuration.limit,
                                          snooze: { [weak self] in self?.snooze(kind, days: $0) },
                                          openBattery: { [weak self] in self?.dismiss(); self?.openBattery() })
        if presenter.show(view, title: "MacCare — \(completion?.title ?? kind.title)", anchor: anchor()) {
            visibleKind = kind
            if !preview { AdditionalAlertReminder(kind).record() }
        }
    }

    private func snooze(_ kind: AdditionalAlertKind, days: Int) {
        if !preview { AdditionalAlertReminder(kind).snooze(days: days) }
        dismiss()
    }

    private func showPreview(_ kind: AdditionalAlertKind) {
        guard !suspended else { return }
        switch kind {
        case .protection: presentBattery(completion: nil, preview: true)
        case .cycle:
            presentBattery(completion: .init(id: UUID(), operation: .topUp, target: 80, createdAt: Date()), preview: true)
        case .cpu:
            let path = "/Applications/Helium.app"
            let row = TrayProcess(id: .init(pid: -1, startedSeconds: 0, startedMicroseconds: 0), name: "Helium", userID: getuid(),
                                  memory: 1, cpuPercent: 184, executable: path + "/Contents/MacOS/Helium")
            processes.replace([.init(process: row, application: .init(pid: -1, name: "Helium", bundleID: "preview.helium", bundlePath: path,
                                                                     executable: row.executable, isRegular: true))], preview: true)
            presentCPU(preview: true)
        }
    }

    func shutdown() {
        stop()
        if let previewObserver { NotificationCenter.default.removeObserver(previewObserver) }
        previewObserver = nil
    }
}
