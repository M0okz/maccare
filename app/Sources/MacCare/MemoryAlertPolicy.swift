import Foundation

struct MemoryAlertPolicy {
    static let enabledKey = "memoryAlert.enabled"
    static let lastShownKey = "memoryAlert.lastShown"
    static let snoozedUntilKey = "memoryAlert.snoozedUntil"
    static let previewNotification = Notification.Name("MacCare.previewMemoryAlert")
    let defaults: UserDefaults
    private var warningSince: TimeInterval?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var enabled: Bool { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }

    mutating func observe(_ level: MemoryPressureLevel?, uptime: TimeInterval) -> Bool {
        guard let level, level != .normal else { warningSince = nil; return false }
        if warningSince == nil || uptime < (warningSince ?? uptime) { warningSince = uptime }
        return level == .critical || uptime - (warningSince ?? uptime) >= 30
    }

    mutating func resetObservation() { warningSince = nil }

    func shouldPresent(now: Date = Date()) -> Bool {
        guard enabled else { return false }
        if let until = defaults.object(forKey: Self.snoozedUntilKey) as? Date, now < until { return false }
        if let last = defaults.object(forKey: Self.lastShownKey) as? Date,
           now.timeIntervalSince(last) < 86_400 { return false }
        return true
    }
    func recordPresentation(at date: Date = Date()) { defaults.set(date, forKey: Self.lastShownKey) }
    func snooze(days: Int, from date: Date = Date()) {
        guard days == 1 || days == 7 else { return }
        defaults.set(Calendar.current.date(byAdding: .day, value: days, to: date), forKey: Self.snoozedUntilKey)
    }
}
