import XCTest
@testable import MacCare

final class MemoryAlertTests: XCTestCase {
    private func withPolicy(_ test: (inout MemoryAlertPolicy) -> Void) {
        let name = testPreferencesSuite("MacCare.MemoryAlertTests")
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var policy = MemoryAlertPolicy(defaults: defaults)
        test(&policy)
    }

    private func candidate(pid: pid_t = 900_001, memory: UInt64 = 1_430_000_000,
                           started: UInt64 = 10, uid: uid_t = getuid(), regular: Bool = true,
                           bundleID: String = "test.editor", bundle: String = "/Applications/Editor.app") -> MemoryAlertCandidate {
        let process = TrayProcess(id: .init(pid: pid, startedSeconds: started, startedMicroseconds: 20),
                                  name: "Editor", userID: uid, memory: memory, cpuPercent: nil,
                                  executable: bundle + "/Contents/MacOS/Editor")
        let app = MemoryAlertApplication(pid: pid, name: "Editor", bundleID: bundleID, bundlePath: bundle,
                                        executable: process.executable, isRegular: regular)
        return MemoryAlertCandidate(process: process, application: app)
    }

    func testPressureFlagsAndLiveRead() {
        XCTAssertEqual(MemoryPressureLevel(rawValue: 1), .normal)
        XCTAssertEqual(MemoryPressureLevel(rawValue: 2), .warning)
        XCTAssertEqual(MemoryPressureLevel(rawValue: 4), .critical)
        XCTAssertNil(MemoryPressureLevel(rawValue: 0))
        XCTAssertNotNil(MemoryPressureLevel.current())
    }

    func testWarningMustPersistAndCriticalDoesNotWait() {
        withPolicy { policy in
            XCTAssertFalse(policy.observe(.warning, uptime: 100))
            XCTAssertFalse(policy.observe(.warning, uptime: 129))
            XCTAssertTrue(policy.observe(.warning, uptime: 130))
            XCTAssertFalse(policy.observe(.normal, uptime: 131))
            XCTAssertFalse(policy.observe(.warning, uptime: 132))
            XCTAssertTrue(policy.observe(.critical, uptime: 133))
        }
    }

    func testUnknownNormalSleepAndClockResetBreakSustainedWarning() {
        withPolicy { policy in
            _ = policy.observe(.warning, uptime: 100)
            XCTAssertFalse(policy.observe(nil, uptime: 129))
            XCTAssertFalse(policy.observe(.warning, uptime: 130))
            policy.resetObservation()
            XCTAssertFalse(policy.observe(.warning, uptime: 200))
            XCTAssertFalse(policy.observe(.warning, uptime: 2))
        }
    }

    func testPersistentDailyReminderAndDisabledPreference() {
        withPolicy { policy in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            XCTAssertTrue(policy.shouldPresent(now: now))
            policy.recordPresentation(at: now)
            let restored = MemoryAlertPolicy(defaults: policy.defaults)
            XCTAssertFalse(restored.shouldPresent(now: now.addingTimeInterval(86_399)))
            XCTAssertTrue(restored.shouldPresent(now: now.addingTimeInterval(86_400)))
            policy.defaults.set(false, forKey: MemoryAlertPolicy.enabledKey)
            XCTAssertFalse(restored.shouldPresent(now: now.addingTimeInterval(90_000)))
        }
    }

    func testDayAndWeekSnoozesPersistWithoutAffectingStorageAlerts() {
        for days in [1, 7] {
            withPolicy { policy in
                let now = Date(timeIntervalSince1970: 1_800_000_000)
                policy.snooze(days: days, from: now)
                let restored = MemoryAlertPolicy(defaults: policy.defaults)
                let end = Calendar.current.date(byAdding: .day, value: days, to: now)!
                XCTAssertFalse(restored.shouldPresent(now: end.addingTimeInterval(-1)))
                XCTAssertTrue(restored.shouldPresent(now: end))
                XCTAssertNil(policy.defaults.object(forKey: StorageAlertPolicy.snoozedUntilKey))
            }
        }
    }

    func testCandidatesAreRankedAndLimitedToThreeEligibleApplications() {
        let rows = [candidate(pid: 900_001, memory: 700_000_000), candidate(pid: 900_002, memory: 2_000_000_000),
                    candidate(pid: 900_003, memory: 3_000_000_000), candidate(pid: 900_004, memory: 1_000_000_000),
                    candidate(pid: 900_005, memory: 100_000_000), candidate(pid: 900_006, regular: false),
                    candidate(pid: 900_007, bundleID: "org.maccare.app"), candidate(pid: 900_008, uid: getuid() + 1),
                    candidate(pid: 900_009, bundle: "/System/Applications/System.app")]
        let ranked = MemoryAlertCandidate.ranked(processes: rows.map(\.process), applications: rows.map(\.application))
        XCTAssertEqual(ranked.map(\.id.pid), [900_003, 900_002, 900_004])
        XCTAssertEqual(candidate().memoryText, "1,43 Go")
    }

    func testQuitValidationRejectsReusedPIDOwnerAndApplicationChanges() {
        let original = candidate()
        XCTAssertTrue(original.matches(live: original.process, application: original.application))
        let restarted = candidate(started: 11)
        XCTAssertFalse(original.matches(live: restarted.process, application: restarted.application))
        let otherUser = candidate(uid: getuid() + 1)
        XCTAssertFalse(original.matches(live: otherUser.process, application: otherUser.application))
        let otherApp = candidate(bundleID: "different.application")
        XCTAssertFalse(original.matches(live: otherApp.process, application: otherApp.application))
        let background = candidate(regular: false)
        XCTAssertFalse(original.matches(live: background.process, application: background.application))
    }

    @MainActor func testNormalAndForceActionsAreScopedToDisplayedCandidates() {
        var requests: [(pid_t, Bool)] = []
        let model = MemoryAlertModel { row, force in requests.append((row.id.pid, force)); return nil }
        let first = candidate(), second = candidate(pid: 900_002), unseen = candidate(pid: 900_003)
        model.replace([first, second])
        model.quit(unseen)
        XCTAssertTrue(requests.isEmpty)
        model.quit(first)
        XCTAssertEqual(requests.map(\.0), [first.id.pid])
        XCTAssertFalse(requests[0].1)
        XCTAssertTrue(model.canForceQuit)
        model.forceQuitDisplayed()
        XCTAssertEqual(requests.map(\.0), [first.id.pid, first.id.pid, second.id.pid])
        XCTAssertTrue(requests[1].1)
        XCTAssertTrue(requests[2].1)
        XCTAssertFalse(model.canForceQuit)
    }

    @MainActor func testPreviewNeverInvokesQuitAndErrorsRemainVisible() {
        var requests = 0
        let model = MemoryAlertModel { _, _ in requests += 1; return "Fermeture refusée" }
        let row = candidate()
        model.replace([row], preview: true)
        model.quit(row); model.forceQuitDisplayed()
        XCTAssertEqual(requests, 0)
        model.replace([row])
        model.quit(row)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(model.message, "Fermeture refusée")
        XCTAssertTrue(model.pending.isEmpty)
    }
}
