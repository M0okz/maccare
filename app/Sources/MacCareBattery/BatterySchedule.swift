import Foundation

public enum BatteryAutomationAction: Codable, Equatable, Sendable {
    case configure(BatteryConfiguration), topUp, discharge, calibrate, disable
    public var isValid: Bool { if case .configure(let value) = self { return value.isValid }; return true }
    public var title: String {
        switch self {
        case .configure(let value): return "Appliquer une limite de \(value.limit) %"
        case .topUp: return "Recharger à 100 % une fois"
        case .discharge: return "Décharger jusqu’à la limite"
        case .calibrate: return "Démarrer l’étalonnage"
        case .disable: return "Désactiver la protection"
        }
    }
}

/// Wall-clock recurrence, tied to the timezone selected when created. At-most-once
/// claims must be persisted BEFORE executing an action. Missed jobs never burst on wake.
public struct BatterySchedule: Codable, Equatable, Identifiable, Sendable {
    public enum Recurrence: String, Codable, CaseIterable, Sendable {
        case once, daily, weekdays, weekly, monthly
        public var title: String {
            switch self {
            case .once: return "Une seule fois"
            case .daily: return "Chaque jour"
            case .weekdays: return "Du lundi au vendredi"
            case .weekly: return "Chaque semaine"
            case .monthly: return "Chaque mois"
            }
        }
    }
    public enum Claim: Equatable, Sendable { case notDue, run, missed }
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var action: BatteryAutomationAction
    public var recurrence: Recurrence
    public var timeZoneID: String
    public var hour: Int
    public var minute: Int
    public var weekday: Int
    public var monthDay: Int
    public var nextRun: Date
    public private(set) var lastClaimed: Date?
    public init(id: UUID = UUID(), name: String, action: BatteryAutomationAction, recurrence: Recurrence,
                firstRun: Date, timeZone: TimeZone = .current, calendar: Calendar = .current) {
        var calendar = calendar; calendar.timeZone = timeZone
        self.id = id; self.name = name; self.action = action; self.recurrence = recurrence
        enabled = true; timeZoneID = timeZone.identifier
        let parts = calendar.dateComponents([.hour, .minute, .weekday, .day], from: firstRun)
        hour = parts.hour ?? 0; minute = parts.minute ?? 0; weekday = parts.weekday ?? 1; monthDay = parts.day ?? 1
        nextRun = firstRun
    }
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 60 && action.isValid &&
        TimeZone(identifier: timeZoneID) != nil && (0...23).contains(hour) && (0...59).contains(minute) &&
        (1...7).contains(weekday) && (1...31).contains(monthDay) && nextRun.timeIntervalSince1970.isFinite
    }
    public func occurrence(after date: Date) -> Date? {
        guard isValid, date.timeIntervalSince1970.isFinite, recurrence != .once,
              let zone = TimeZone(identifier: timeZoneID) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let day = calendar.startOfDay(for: date)
        for offset in 0...370 {
            guard let candidateDay = calendar.date(byAdding: .day, value: offset, to: day) else { continue }
            let parts = calendar.dateComponents([.weekday, .day], from: candidateDay)
            if recurrence == .weekdays && !(2...6).contains(parts.weekday ?? 0) { continue }
            if recurrence == .weekly && parts.weekday != weekday { continue }
            if recurrence == .monthly && parts.day != monthDay { continue }
            guard let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: candidateDay,
                                                matchingPolicy: .nextTimePreservingSmallerComponents,
                                                repeatedTimePolicy: .first, direction: .forward), candidate > date else { continue }
            return candidate
        }
        return nil
    }
    public mutating func preserveProgress(from existing: Self) {
        guard existing.id == id, let last = existing.lastClaimed,
              lastClaimed.map({ $0 < last }) != false else { return }
        lastClaimed = last
        if nextRun <= last {
            nextRun = existing.nextRun
            if recurrence == .once { enabled = false }
        }
    }
    public mutating func claim(at now: Date, maximumDelay: TimeInterval = 600) -> Claim {
        guard enabled, isValid, now.timeIntervalSince1970.isFinite, maximumDelay.isFinite, maximumDelay >= 0,
              nextRun <= now, lastClaimed.map({ nextRun > $0 }) != false else { return .notDue }
        let due = nextRun
        lastClaimed = due
        if let next = occurrence(after: now) { nextRun = next } else { enabled = false }
        return now.timeIntervalSince(due) <= maximumDelay ? .run : .missed
    }
}
