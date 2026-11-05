import Foundation

/// Les délais sont persistants : relancer MacCare ne réaffiche pas la même alerte.
struct StorageAlertPolicy {
    static let enabledKey = "storageAlert.enabled"
    static let lastShownKey = "storageAlert.lastShown"
    static let snoozedUntilKey = "storageAlert.snoozedUntil"
    static let previewNotification = Notification.Name("MacCare.previewStorageAlert")
    static let reminderInterval: TimeInterval = 86_400

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var enabled: Bool { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }

    static func isLow(free: UInt64, total: UInt64) -> Bool {
        guard total > 0, free <= total else { return false }
        return Double(free) / Double(total) <= 0.10 || free < 10_000_000_000
    }

    func shouldPresent(free: UInt64, total: UInt64, now: Date = Date()) -> Bool {
        guard enabled, Self.isLow(free: free, total: total) else { return false }
        if let until = defaults.object(forKey: Self.snoozedUntilKey) as? Date, now < until { return false }
        if let last = defaults.object(forKey: Self.lastShownKey) as? Date,
           now.timeIntervalSince(last) < Self.reminderInterval { return false }
        return true
    }

    func recordPresentation(at date: Date = Date()) { defaults.set(date, forKey: Self.lastShownKey) }

    func snooze(days: Int, from date: Date = Date()) {
        guard days == 1 || days == 7 else { return }
        let until = Calendar.current.date(byAdding: .day, value: days, to: date)
        defaults.set(until, forKey: Self.snoozedUntilKey)
    }
}
