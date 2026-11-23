import XCTest
@testable import MacCare

final class ThermalAlertTests: XCTestCase {
    @MainActor private final class Episode {
        let suite = testPreferencesSuite("MacCare.ThermalAlertTests")
        lazy var defaults = UserDefaults(suiteName: suite)!
        let center = NotificationCenter()
        var state: ProcessInfo.ThermalState = .nominal
        var uptime: TimeInterval = 0
        var canPresent = true
        var presentations: [ProcessInfo.ThermalState] = []
        var reads = 0
        var recoveries = 0
        lazy var monitor = makeMonitor()

        func makeMonitor() -> ThermalAlertMonitor {
            ThermalAlertMonitor(defaults: defaults, center: center, readState: { [unowned self] in
                self.reads += 1
                return self.state
            }, uptime: { [unowned self] in self.uptime }, present: { [unowned self] state in
                guard self.canPresent else { return false }
                self.presentations.append(state)
                return true
            }, recovered: { [unowned self] in self.recoveries += 1 })
        }

        func observe(_ value: ProcessInfo.ThermalState, at time: TimeInterval) {
            state = value
            uptime = time
            center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        }

        func finish() {
            monitor.setEnabled(false)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    @MainActor func testContinuousSeriousAndCriticalShareAnEpisode() {
        let f = Episode()
        defer { f.finish() }
        f.monitor.setEnabled(true)
        f.observe(.serious, at: 1)
        f.observe(.serious, at: 60)
        XCTAssertTrue(f.presentations.isEmpty)
        f.observe(.fair, at: 61)
        f.observe(.serious, at: 62)
        f.observe(.serious, at: 121)
        XCTAssertTrue(f.presentations.isEmpty)
        f.observe(.serious, at: 122)
        f.observe(.critical, at: 123)
        XCTAssertEqual(f.presentations, [.serious])
        f.observe(.nominal, at: 124)
        f.observe(.serious, at: 125)
        f.observe(.critical, at: 126)
        XCTAssertEqual(f.presentations, [.serious, .critical])
        XCTAssertEqual(f.recoveries, 2)
    }

    @MainActor func testDeadlineFiresWithoutAnotherThermalReading() async throws {
        let f = Episode()
        defer { f.finish() }
        f.state = .serious
        f.monitor.setEnabled(true)
        // Advance the monotonic clock and leave a short real interval on the run-loop timer.
        f.observe(.serious, at: ThermalAlertMonitor.seriousDuration - 0.03)
        f.uptime = ThermalAlertMonitor.seriousDuration
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(f.presentations, [.serious])
        XCTAssertEqual(f.reads, 3)
    }

    @MainActor func testSleepRestartsTheDelayAndRelaunchPreservesADeliveredEpisode() {
        let f = Episode()
        defer { f.finish() }
        f.state = .serious
        f.monitor.setEnabled(true)
        f.monitor.setEnabled(false)
        f.uptime = 500
        f.monitor.setEnabled(true)
        f.observe(.serious, at: 559)
        XCTAssertTrue(f.presentations.isEmpty)
        f.observe(.critical, at: 560)
        f.monitor.setEnabled(false)
        f.monitor = f.makeMonitor()
        f.monitor.setEnabled(true)
        XCTAssertEqual(f.presentations, [.critical])
        f.observe(.fair, at: 561)
        f.observe(.critical, at: 562)
        XCTAssertEqual(f.presentations, [.critical, .critical])
    }

    @MainActor func testBusyPresentationRetriesWithoutPollingOrConsumingTheEpisode() async throws {
        let f = Episode()
        defer { f.finish() }
        f.state = .critical
        f.canPresent = false
        f.monitor.setEnabled(true)
        f.canPresent = true
        XCTAssertTrue(f.presentations.isEmpty)
        try await Task.sleep(for: .milliseconds(5400))
        XCTAssertEqual(f.presentations, [.critical])
        XCTAssertEqual(f.reads, 2)
    }

    @MainActor func testSnoozeBlocksCriticalAndDisabledMonitorIgnoresEvents() {
        let f = Episode()
        defer { f.finish() }
        AdditionalAlertReminder(.thermal, defaults: f.defaults).snooze(days: 1)
        f.state = .critical
        f.monitor.setEnabled(true)
        XCTAssertTrue(f.presentations.isEmpty)
        f.monitor.setEnabled(false)
        f.observe(.nominal, at: 20)
        XCTAssertEqual(f.reads, 2)
        f.defaults.removeObject(forKey: "additionalAlert.thermal.snoozedUntil")
        f.observe(.critical, at: 30)
        XCTAssertTrue(f.presentations.isEmpty)
        f.monitor.setEnabled(true)
        XCTAssertEqual(f.presentations, [.critical])
    }
}
