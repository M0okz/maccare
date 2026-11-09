import Foundation

struct AdditionalAlertReminder {
    let kind: AdditionalAlertKind
    let defaults: UserDefaults
    init(_ kind: AdditionalAlertKind, defaults: UserDefaults = .standard) { self.kind = kind; self.defaults = defaults }
    var enabled: Bool { defaults.object(forKey: kind.enabledKey) as? Bool ?? kind.enabledByDefault }
    private var prefix: String { "additionalAlert.\(kind.rawValue)" }
    func shouldPresent(at date: Date = Date()) -> Bool {
        guard enabled else { return false }
        if let until = defaults.object(forKey: prefix + ".snoozedUntil") as? Date, date < until { return false }
        if kind != .cycle && kind != .deviceBattery, let last = defaults.object(forKey: prefix + ".lastShown") as? Date,
           date.timeIntervalSince(last) < 86_400 { return false }
        return true
    }
    func record(at date: Date = Date()) { defaults.set(date, forKey: prefix + ".lastShown") }
    func snooze(days: Int, from date: Date = Date()) {
        guard days == 1 || days == 7 else { return }
        defaults.set(Calendar.current.date(byAdding: .day, value: days, to: date), forKey: prefix + ".snoozedUntil")
    }
}
