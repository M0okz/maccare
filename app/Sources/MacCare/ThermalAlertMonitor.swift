import Foundation

/// Les changements d’état viennent de macOS. Un réveil ponctuel suffit pour confirmer
/// la durée, attendre la fin d’un report ou réessayer une présentation occupée.
@MainActor
final class ThermalAlertMonitor {
    static let seriousDuration: TimeInterval = 60
    private static let announcedKey = "additionalAlert.thermal.episodeAnnounced"
    private let defaults: UserDefaults
    private let center: NotificationCenter
    private let readState: () -> ProcessInfo.ThermalState
    private let uptime: () -> TimeInterval
    private let present: (ProcessInfo.ThermalState) -> Bool
    private let recovered: () -> Void

    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var state: ProcessInfo.ThermalState = .nominal
    private var seriousSince: TimeInterval?

    init(defaults: UserDefaults = .standard, center: NotificationCenter = .default,
         readState: @escaping () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState },
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         present: @escaping (ProcessInfo.ThermalState) -> Bool, recovered: @escaping () -> Void) {
        self.defaults = defaults
        self.center = center
        self.readState = readState
        self.uptime = uptime
        self.present = present
        self.recovered = recovered
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled {
            if let observer { center.removeObserver(observer) }
            observer = nil
            cancelTimer()
            seriousSince = nil
            state = .nominal
            return
        }
        guard observer == nil else { return }
        // Foundation exige une première lecture avant l’abonnement. La seconde
        // couvre un changement survenu pendant l’installation de l’observateur.
        _ = readState()
        observer = center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                      object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stateChanged() }
        }
        stateChanged()
    }

    private func stateChanged() {
        let previous = state
        state = readState()
        if state == .nominal || state == .fair {
            if defaults.bool(forKey: Self.announcedKey) { defaults.removeObject(forKey: Self.announcedKey) }
            if previous == .serious || previous == .critical { recovered() }
        }
        if state != .serious { seriousSince = nil }
        else if seriousSince == nil { seriousSince = uptime() }
        evaluate()
    }

    private func evaluate() {
        cancelTimer()
        guard observer != nil, state == .serious || state == .critical,
              !defaults.bool(forKey: Self.announcedKey) else { return }
        let reminder = AdditionalAlertReminder(.thermal, defaults: defaults)
        guard reminder.enabled else { return }
        let remaining = seriousSince.map { Self.seriousDuration - (uptime() - $0) } ?? 0
        let delay = max(remaining, reminder.snoozedUntil?.timeIntervalSinceNow ?? 0)
        if delay > 0 {
            schedule(after: delay)
        } else if present(state) {
            defaults.set(true, forKey: Self.announcedKey)
        } else {
            schedule(after: 5)
        }
    }

    private func schedule(after delay: TimeInterval) {
        let timer = Timer(fire: Date().addingTimeInterval(delay), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }
}
