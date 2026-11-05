import XCTest
import MacCareMaintenance
@testable import MacCare

final class LocalSnapshotMaintenanceTests: XCTestCase {
    private let snapshots = "Snapshots for disk /:\ncom.apple.TimeMachine.2026-11-02-100000.local\ncom.apple.TimeMachine.2026-11-02-110000.local\n"

    func testDisabledPreferenceSurvivesReloadAndBlocksPreviouslyConfirmedRequest() throws {
        let name = testPreferencesSuite("maccare.snapshot-preferences")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(PerformancePreferences.includeLocalSnapshots(in: defaults))
        defaults.set(false, forKey: PerformancePreferences.localSnapshotsKey)
        let reloaded = try XCTUnwrap(UserDefaults(suiteName: name))
        XCTAssertFalse(PerformancePreferences.includeLocalSnapshots(in: reloaded))
        XCTAssertFalse(PerformancePreferences.allowsLocalSnapshots(confirmed: true, defaults: reloaded))
        defaults.set(true, forKey: PerformancePreferences.localSnapshotsKey)
        XCTAssertFalse(PerformancePreferences.allowsLocalSnapshots(confirmed: false, defaults: defaults))
        XCTAssertTrue(PerformancePreferences.allowsLocalSnapshots(confirmed: true, defaults: defaults))
    }

    @MainActor func testDisablingAfterConfirmationPreventsHelperCallAtExecution() async throws {
        let name = testPreferencesSuite("maccare.snapshot-routing")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: PerformancePreferences.localSnapshotsKey)
        var calls = 0
        let model = PerformanceTasksModel(defaults: defaults, executeSnapshots: {
            calls += 1
            return .init(.completed, "fixture: snapshots requested")
        })
        model.run([.purgeable], includeLocalSnapshots: true)
        defaults.set(false, forKey: PerformancePreferences.localSnapshotsKey)
        try await finish(model)
        XCTAssertEqual(calls, 0)
        defaults.set(true, forKey: PerformancePreferences.localSnapshotsKey)
        model.run([.purgeable], includeLocalSnapshots: false)
        try await finish(model)
        XCTAssertEqual(calls, 0, "Enabling a setting cannot broaden a prior cache-only confirmation")
        model.run([.purgeable], includeLocalSnapshots: true)
        try await finish(model)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.reports[.purgeable]?.status, .completed)
    }

    @MainActor private func finish(_ model: PerformanceTasksModel) async throws {
        for _ in 0..<200 {
            if model.running == nil { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("La tâche injectée ne se termine pas")
    }

    func testHelperUsesOnlyLocalThinningWithFixedVolumeAndBoundedDuration() {
        let command = LocalSnapshotMaintenance.thinningCommand
        XCTAssertEqual(command.executable, "/usr/bin/tmutil")
        XCTAssertEqual(command.arguments, ["thinlocalsnapshots", "/", String(Int64.max), "4"])
        XCTAssertEqual(command.timeout, 600)
        XCTAssertEqual(PerformanceTask.purgeable.requiresHelper(includeLocalSnapshots: true), true)
        XCTAssertEqual(PerformanceTask.purgeable.requiresHelper(includeLocalSnapshots: false), false)
        // Never use diskutil deleteSnapshot or a caller-selected disk or snapshot ID.
        XCTAssertEqual(PrivilegedMaintenance.commands(for: .purgeable, authenticatedUID: 501), [command])
    }

    func testUnrelatedAPFSSnapshotsAreNotCountedAsTimeMachinePoints() {
        XCTAssertEqual(LocalSnapshotMaintenance.snapshotCount(in: snapshots + "com.apple.os.update.protected\n"), 2)
    }

    func testEmptyInventoryDoesNotInvokeThinning() {
        var calls: [MaintenanceCommand] = []
        let report = LocalSnapshotMaintenance.execute(run: { command in
            calls.append(command)
            return .init(status: 0, text: "Snapshots for disk /:\n")
        }, freeBytes: { 100 })
        XCTAssertEqual(report.status, .completed)
        XCTAssertEqual(calls, [LocalSnapshotMaintenance.listingCommand])
        XCTAssertTrue(report.message.contains("Aucun instantané"))
    }

    func testFailedInventoryDoesNotInvokeThinning() {
        var calls = 0
        let report = LocalSnapshotMaintenance.execute(run: { _ in
            calls += 1
            return .init(status: 1, text: "fixture: access denied")
        }, freeBytes: { nil })
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(report.status, .failed)
    }

    func testSuccessfulThinningReportsActualBeforeAfterObservations() {
        var calls: [MaintenanceCommand] = []
        var measurements = 0
        let report = LocalSnapshotMaintenance.execute(run: { command in
            calls.append(command)
            if calls.count == 1 { return .init(status: 0, text: snapshots) }
            if calls.count == 2 { return .init(status: 0, text: "Thinned local snapshots:\nfixture") }
            return .init(status: 0, text: "Snapshots for disk /:\n")
        }, freeBytes: {
            measurements += 1
            return measurements == 1 ? 100 : 1124
        })
        XCTAssertEqual(report.status, .completed)
        XCTAssertEqual(calls, [LocalSnapshotMaintenance.listingCommand, LocalSnapshotMaintenance.thinningCommand, LocalSnapshotMaintenance.listingCommand])
        XCTAssertTrue(report.details.contains("2 avant, 0 après"))
        XCTAssertTrue(report.details.contains("1024 octets"))
    }

    func testThinningFailureIsPartialBecauseRemovalMayAlreadyHaveOccurred() {
        var calls = 0
        let report = LocalSnapshotMaintenance.execute(run: { _ in
            calls += 1
            return calls == 1 ? .init(status: 0, text: snapshots) : .init(status: 1, text: "fixture")
        }, freeBytes: { nil })
        XCTAssertEqual(report.status, .partial)
        XCTAssertFalse(report.succeeded)
    }

    func testSuccessfulThinningWithFailedFinalInventoryIsPartial() {
        var calls = 0
        let report = LocalSnapshotMaintenance.execute(run: { _ in
            calls += 1
            switch calls {
            case 1: return .init(status: 0, text: snapshots)
            case 2: return .init(status: 0)
            default: return .init(status: 1)
            }
        }, freeBytes: { nil })
        XCTAssertEqual(report.status, .partial)
    }

    func testSnapshotModeRemainsAvailableWithNoCachesButRequiresHelper() {
        func availability(_ helper: Bool) -> String? {
            PerformanceTaskPresentation.unavailable(.purgeable, helperEnabled: helper, fullDiskGranted: true,
                mailRunning: false, preparing: false, cacheCount: 0, cacheError: "fixture cache error", includeLocalSnapshots: true)
        }
        XCTAssertNil(availability(true))
        XCTAssertNotNil(availability(false))
        XCTAssertTrue(PerformanceTaskPresentation.effect(.purgeable, includeLocalSnapshots: true).contains("restauration"))
        XCTAssertTrue(PerformanceTaskPresentation.effect(.purgeable, includeLocalSnapshots: false).contains("conservés"))
    }

    func testCombiningIndependentStepsNeverHidesPartialFailure() {
        let success = MaintenanceReport(.completed, "fixture success")
        let partial = MaintenanceReport(.partial, "fixture partial")
        let failed = MaintenanceReport(.failed, "fixture failed")
        XCTAssertEqual(PurgeableMaintenanceReport.combine(snapshots: success, caches: nil).status, .completed)
        XCTAssertEqual(PurgeableMaintenanceReport.combine(snapshots: success, caches: failed).status, .partial)
        XCTAssertEqual(PurgeableMaintenanceReport.combine(snapshots: partial, caches: nil).status, .partial)
        XCTAssertEqual(PurgeableMaintenanceReport.combine(snapshots: failed, caches: failed).status, .failed)
    }
}
