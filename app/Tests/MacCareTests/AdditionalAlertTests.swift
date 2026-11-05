import XCTest
import MacCareBattery
import ServiceManagement
@testable import MacCare

final class AdditionalAlertTests: XCTestCase {
    private func status(percent: Int = 100, onAC: Bool = true) -> BatteryProtectionStatus {
        .init(snapshot: .init(percent: percent, onAC: onAC, temperature: 30), supported: true,
              active: true, configuration: .init(limit: 80), ownedByCaller: true)
    }
    private func observation(_ status: BatteryProtectionStatus?, expected: Bool = true,
                             helper: Bool = true, cancellation: Int = 0, terminating: Bool = false) -> BatteryAlertObservation {
        .init(expected: expected, helperReady: helper, status: status, cancellation: cancellation, terminating: terminating)
    }
    private func cycle(_ phase: BatteryCycleStatus.Phase) -> BatteryCycleStatus {
        var value = BatteryCycle(target: 80, now: 0).status; value.phase = phase; return value
    }

    func testCPURequiresTwoContinuousMinutesAndFreshSamples() {
        var condition = CPUAlertCondition()
        for second in 0..<120 { condition.observe(fraction: 0.85, sampledAt: Double(second)) }
        XCTAssertFalse(condition.sustained)
        condition.observe(fraction: 0.9, sampledAt: 120)
        XCTAssertTrue(condition.sustained)
        XCTAssertTrue(condition.isFresh(at: 123))
        XCTAssertFalse(condition.isFresh(at: 124))
        condition.observe(fraction: 0.84, sampledAt: 121)
        XCTAssertFalse(condition.sustained)
    }

    func testCPUGapsInvalidSamplesAndSleepResetTheWindow() {
        for invalid in [Double.nan, .infinity, -0.1, 1.5] {
            var condition = CPUAlertCondition()
            condition.observe(fraction: invalid, sampledAt: 10)
            XCTAssertFalse(condition.sustained)
            XCTAssertFalse(condition.isFresh(at: 10))
        }
        var condition = CPUAlertCondition()
        condition.observe(fraction: 1, sampledAt: 0)
        condition.observe(fraction: 1, sampledAt: 120)
        XCTAssertFalse(condition.sustained)
        condition.observe(fraction: nil, sampledAt: 121)
        XCTAssertFalse(condition.isFresh(at: 121))
        condition.reset()
        XCTAssertFalse(condition.sustained)
    }

    func testIndependentRemindersAndEveryDistinctCompletion() {
        let suite = "MacCare.AdditionalAlertTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cpu = AdditionalAlertReminder(.cpu, defaults: defaults)
        XCTAssertTrue(cpu.shouldPresent(at: now))
        cpu.record(at: now)
        XCTAssertFalse(AdditionalAlertReminder(.cpu, defaults: defaults).shouldPresent(at: now.addingTimeInterval(86_399)))
        XCTAssertTrue(cpu.shouldPresent(at: now.addingTimeInterval(86_400)))
        XCTAssertTrue(AdditionalAlertReminder(.protection, defaults: defaults).shouldPresent(at: now))
        let completion = AdditionalAlertReminder(.cycle, defaults: defaults)
        completion.record(at: now)
        XCTAssertTrue(completion.shouldPresent(at: now.addingTimeInterval(1)))
        completion.snooze(days: 7, from: now)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now)!
        XCTAssertFalse(completion.shouldPresent(at: end.addingTimeInterval(-1)))
        XCTAssertTrue(completion.shouldPresent(at: end))
        defaults.set(false, forKey: AdditionalAlertKind.protection.enabledKey)
        XCTAssertFalse(AdditionalAlertReminder(.protection, defaults: defaults).shouldPresent(at: end))
    }

    func testProtectionFailureRequiresThirtySecondsAndRecoveryClearsIt() {
        var detector = BatteryAlertDetector()
        let failure = observation(nil, helper: false)
        _ = detector.observe(failure, uptime: 0)
        _ = detector.observe(failure, uptime: 29)
        XCTAssertFalse(detector.interrupted)
        _ = detector.observe(failure, uptime: 30)
        XCTAssertTrue(detector.interrupted)
        _ = detector.observe(observation(status()), uptime: 31)
        XCTAssertFalse(detector.interrupted)
    }

    func testVoluntaryDisableAndTerminationCannotTriggerInterruption() {
        var detector = BatteryAlertDetector()
        _ = detector.observe(observation(nil), uptime: 0)
        _ = detector.observe(observation(nil, expected: false), uptime: 50)
        XCTAssertFalse(detector.interrupted)
        _ = detector.observe(observation(nil, terminating: true), uptime: 100)
        XCTAssertFalse(detector.interrupted)
    }

    func testNormalChargePausesAndNativeRegistrationGraceAreNotFailures() {
        var detector = BatteryAlertDetector()
        var paused = status(percent: 80, onAC: false); paused.suspended = true
        _ = detector.observe(observation(paused), uptime: 0)
        _ = detector.observe(observation(paused), uptime: 100)
        XCTAssertFalse(detector.interrupted)
        var native = status()
        native.capabilities = .init(backend: .nativePolicy)
        native.chargeApplication = .init(requestedLimit: 80, registeredLimit: 100, elapsed: 20)
        XCTAssertTrue(observation(native).healthy)
        native.chargeApplication = .init(requestedLimit: 80, registeredLimit: 100, elapsed: 200)
        XCTAssertFalse(observation(native).healthy)
        _ = detector.observe(observation(native), uptime: 200)
        _ = detector.observe(observation(native), uptime: 230)
        XCTAssertTrue(detector.interrupted)
    }

    func testTopUpCompletesOnceWithoutEnablingDisabledCycles() {
        var detector = BatteryAlertDetector()
        var running = status(percent: 99); running.topUp = true
        XCTAssertNil(detector.observe(observation(running), uptime: 0, cyclesEnabled: false))
        let finished = detector.observe(observation(status()), uptime: 15, cyclesEnabled: false)
        XCTAssertEqual(finished?.operation, .topUp)
        XCTAssertEqual(finished?.target, 80)
        XCTAssertNil(detector.observe(observation(status()), uptime: 30, cyclesEnabled: false))
    }

    func testTopUpWaitsForNativeLimitRegistration() {
        var detector = BatteryAlertDetector()
        var running = status(percent: 99); running.topUp = true
        _ = detector.observe(observation(running), uptime: 0)
        var finished = status()
        finished.capabilities = .init(backend: .nativePolicy)
        finished.chargeApplication = .init(requestedLimit: 80, registeredLimit: 100, elapsed: 0)
        XCTAssertNil(detector.observe(observation(finished), uptime: 15))
        finished.chargeApplication = .init(requestedLimit: 80, registeredLimit: 80, elapsed: 10)
        XCTAssertEqual(detector.observe(observation(finished), uptime: 30)?.operation, .topUp)
    }

    func testCancellationUnpluggingErrorsAndRestorationAreNotCompletions() {
        var running = status(percent: 99); running.topUp = true
        var failed = status(); failed.error = "Assistant indisponible"
        var restoring = status(); restoring.restoring = true
        let invalid = [observation(status(), cancellation: 1), observation(status(onAC: false)),
                       observation(failed), observation(restoring), observation(status(), expected: false)]
        for next in invalid {
            var detector = BatteryAlertDetector()
            _ = detector.observe(observation(running), uptime: 0)
            XCTAssertNil(detector.observe(next, uptime: 15))
        }
    }

    func testCycleCompletionRequiresTerminalPhaseAndPowerReturn() {
        var detector = BatteryAlertDetector()
        var running = status(percent: 85); running.cycle = cycle(.dischargingToLimit)
        _ = detector.observe(observation(running), uptime: 0, cyclesEnabled: true)
        var finished = status(percent: 80, onAC: false); finished.message = "Cycle terminé · limite rétablie"
        XCTAssertNil(detector.observe(observation(finished), uptime: 15, cyclesEnabled: true))
        finished.snapshot.onAC = true; finished.message = "Charge suspendue · limite atteinte"
        XCTAssertEqual(detector.observe(observation(finished), uptime: 30, cyclesEnabled: true)?.operation, .discharge)
        XCTAssertNil(detector.observe(observation(finished), uptime: 45, cyclesEnabled: true))
    }

    func testDisabledCyclesEarlyPhasesAndExpiredPowerReturnNeverReportSuccess() {
        var running = status(percent: 85); running.cycle = cycle(.returningToLimit)
        var finished = status(percent: 80); finished.message = "Cycle terminé · limite rétablie"
        var detector = BatteryAlertDetector()
        _ = detector.observe(observation(running), uptime: 0, cyclesEnabled: false)
        XCTAssertNil(detector.observe(observation(finished), uptime: 15, cyclesEnabled: false))
        running.cycle = cycle(.chargingToFull)
        detector.reset()
        _ = detector.observe(observation(running), uptime: 0, cyclesEnabled: true)
        XCTAssertNil(detector.observe(observation(finished), uptime: 15, cyclesEnabled: true))
        running.cycle = cycle(.returningToLimit); finished.snapshot.onAC = false
        detector.reset()
        _ = detector.observe(observation(running), uptime: 0, cyclesEnabled: true)
        _ = detector.observe(observation(finished), uptime: 15, cyclesEnabled: true)
        finished.snapshot.onAC = true
        XCTAssertNil(detector.observe(observation(finished), uptime: 200, cyclesEnabled: true))
    }

    func testCalibrationCompletesAtItsFinalLimitIncludingOneHundredPercent() {
        for target in [80, 100] {
            var detector = BatteryAlertDetector()
            var running = status(percent: 100)
            var phase = cycle(target == 100 ? .rechargingToFull : .returningToLimit)
            phase.target = target
            running.cycle = phase
            running.configuration = .init(limit: target)
            _ = detector.observe(observation(running), uptime: 0, cyclesEnabled: true)
            var finished = status(percent: target)
            finished.configuration = .init(limit: target)
            finished.message = "Cycle terminé · limite rétablie"
            let result = detector.observe(observation(finished), uptime: 15, cyclesEnabled: true)
            XCTAssertEqual(result?.operation, .calibration)
            XCTAssertEqual(result?.target, target)
        }
    }

    func testCPUAttributionUsesCPUAndDoesNotRequireLargeMemory() {
        let path = "/Applications/Editor.app"
        func row(_ pid: pid_t, _ cpu: Double) -> TrayProcess {
            .init(id: .init(pid: pid, startedSeconds: 1, startedMicroseconds: 1), name: "Editor", userID: getuid(),
                  memory: 1, cpuPercent: cpu, executable: path + "/Contents/MacOS/Editor")
        }
        let rows = [row(900_001, 180), row(900_002, 250), row(900_003, .nan), row(900_004, 49)]
        let apps = rows.map { MemoryAlertApplication(pid: $0.id.pid, name: "Editor", bundleID: "test.editor", bundlePath: path,
                                                     executable: $0.executable, isRegular: true) }
        XCTAssertEqual(CPUAlertRanking.candidates(rows, applications: apps).map(\.id.pid), [900_002, 900_001])
    }

    @MainActor func testBatteryAlertIntentSurvivesLostConnectionAndExplicitDisableClearsIt() async {
        let suite = "MacCare.AlertIntentTests.\(UUID())", client = AlertClient()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BatteryModel(defaults: defaults, monitor: false, client: client)
        XCTAssertFalse(model.protectionExpectedForAlerts)
        await model.perform(.enable)
        XCTAssertTrue(model.protectionExpectedForAlerts)
        client.fail = true
        await model.refresh(force: true)
        XCTAssertTrue(model.protectionExpectedForAlerts)
        XCTAssertNil(model.protection)
        client.fail = false
        await model.perform(.cancelTopUp)
        XCTAssertEqual(model.alertCancellation, 1)
        await model.perform(.disable)
        XCTAssertFalse(model.protectionExpectedForAlerts)
        XCTAssertEqual(model.alertCancellation, 2)
    }
}

@MainActor private final class AlertClient: BatteryClient {
    var status: SMAppService.Status = .enabled
    var fail = false
    var active = false
    func snapshot() async -> BatterySnapshot { .init(percent: 80, onAC: true, temperature: 30) }
    func request(_ command: BatteryCommand, configuration: BatteryConfiguration?, sessionID: UUID) async throws -> BatteryProtectionStatus {
        if fail { throw NSError(domain: "test", code: 1) }
        if command == .enable { active = true }
        if command == .disable { active = false }
        return .init(snapshot: await snapshot(), supported: true, active: active,
                     configuration: active ? .init() : nil, ownedByCaller: active)
    }
    func prepareProtection() async throws { }
    func register() throws { }
    func openApproval() { }
}
