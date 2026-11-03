import Foundation
import Testing
import MacCareBattery

struct BatteryScheduleTests {
    private let zone = TimeZone(identifier: "Europe/Paris")!
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    @Test func claimsOnceAndDoesNotReplayAfterRestart() throws {
        let due = date("2026-11-04T08:00:00Z")
        var schedule = BatterySchedule(name: "Départ", action: .topUp, recurrence: .once, firstRun: due, timeZone: zone)
        #expect(schedule.claim(at: due.addingTimeInterval(-1)) == .notDue)
        #expect(schedule.claim(at: due) == .run)
        let restored = try JSONDecoder().decode(BatterySchedule.self, from: JSONEncoder().encode(schedule))
        var copy = restored
        #expect(copy.claim(at: due.addingTimeInterval(1)) == .notDue)
        #expect(copy.enabled == false)
    }
    @Test func missedCalibrationIsSkippedAndNextDailyJobRemainsScheduled() {
        let due = date("2026-11-04T08:00:00Z")
        var schedule = BatterySchedule(name: "Étalonnage", action: .calibrate, recurrence: .daily, firstRun: due, timeZone: zone)
        let wake = due.addingTimeInterval(3 * 86400 + 3600)
        #expect(schedule.claim(at: wake) == .missed)
        #expect(schedule.nextRun > wake)
        #expect(schedule.claim(at: wake) == .notDue)
    }
    @Test func wallTimeSurvivesSpringDSTAndAutumnDoesNotFireTwice() throws {
        let first = date("2026-03-28T08:00:00Z")
        var schedule = BatterySchedule(name: "Matin", action: .topUp, recurrence: .daily, firstRun: first, timeZone: zone)
        #expect(schedule.occurrence(after: first) == date("2026-03-29T07:00:00Z"))
        let autumn = date("2026-10-24T00:30:00Z")
        schedule = BatterySchedule(name: "Nuit", action: .topUp, recurrence: .daily, firstRun: autumn, timeZone: zone)
        let next = try #require(schedule.occurrence(after: autumn))
        #expect(next == date("2026-10-25T00:30:00Z"))
        #expect(schedule.occurrence(after: next) == date("2026-10-26T01:30:00Z"))
    }
    @Test func weekendsAreSkippedAndMonth31NeverRunsOnAnotherDay() {
        let friday = date("2026-11-06T08:00:00Z")
        let weekday = BatterySchedule(name: "Travail", action: .topUp, recurrence: .weekdays, firstRun: friday, timeZone: zone)
        #expect(weekday.occurrence(after: friday) == date("2026-11-09T08:00:00Z"))
        let january = date("2027-01-31T08:00:00Z")
        let monthly = BatterySchedule(name: "Mensuel", action: .topUp, recurrence: .monthly, firstRun: january, timeZone: zone)
        #expect(monthly.occurrence(after: january) == date("2027-03-31T07:00:00Z"))
    }
    @Test func invalidSettingsCannotClaimOrExecute() {
        var schedule = BatterySchedule(name: "", action: .topUp, recurrence: .daily, firstRun: .now, timeZone: zone)
        #expect(schedule.isValid == false)
        #expect(schedule.claim(at: .distantFuture) == .notDue)
        schedule.name = "Valide"; schedule.hour = 24
        #expect(schedule.isValid == false)
    }
}
