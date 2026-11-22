import XCTest
@testable import MacCare

final class TrayProcessesTests: XCTestCase {
    func testHomeRanksDistinctApplicationsIndependentlyOfRowOrder() {
        func process(_ pid: pid_t, _ cpu: Double?, _ path: String) -> TrayProcess {
            TrayProcess(id: .init(pid: pid, startedSeconds: 1, startedMicroseconds: 0),
                        name: "Processus", userID: getuid(), memory: 0, cpuPercent: cpu, executable: path)
        }
        let rows = [
            process(1, 30, "/Applications/A.app/Contents/MacOS/A"),
            process(2, 60, "/Applications/A.app/Contents/Helpers/Agent.app/Contents/MacOS/Agent"),
            process(3, 41, "/Applications/B.app/Contents/MacOS/B"),
            process(4, 70, "/Applications/C.app/Contents/MacOS/C"),
            process(5, 70, "/Applications/D.app/Contents/MacOS/D"),
            process(6, 40, "/Applications/E.app/Contents/MacOS/E"),
            process(7, nil, "/Applications/F.app/Contents/MacOS/F"),
            process(8, 150, "/usr/bin/yes")
        ]
        let leaders = HomeCPUApplication.leaders(in: rows.reversed())
        XCTAssertEqual(leaders.map(\.name), ["A", "C", "D"])
        XCTAssertEqual(leaders.map(\.cpu), [90, 70, 70])
        XCTAssertTrue(HomeCPUApplication.leaders(in: Array(rows.suffix(3))).isEmpty)
    }

    func testHomeSizesUseDecimalsOnlyAboveOneGigabyte() {
        let threshold: UInt64 = 1_000_000_000
        XCTAssertEqual(humanSize(451_750_000, fractionalAbove: threshold), "452\u{00A0}Mo")
        XCTAssertEqual(humanSize(threshold, fractionalAbove: threshold), "1\u{00A0}Go")
        XCTAssertEqual(humanSize(1_250_000_000, fractionalAbove: threshold), "1,25\u{00A0}Go")
        XCTAssertEqual(humanSize(451_750_000), "451,8\u{00A0}Mo")
    }

    func testLiveProcessMeasurementsAndProtectedSelf() async throws {
        let sampler = TrayProcessSampler()
        _ = await sampler.sample()
        try await Task.sleep(for: .seconds(2))
        let rows = await sampler.sample()
        let own = try XCTUnwrap(rows.first { $0.id.pid == getpid() })
        XCTAssertFalse(own.canQuit)
        XCTAssertGreaterThan(own.memory, 0)
        XCTAssertNotNil(own.cpuPercent)
        XCTAssertGreaterThanOrEqual(own.cpuPercent ?? -1, 0)
    }

    func testDashboardReceivesOnlyFreshProcessSamplesWithoutRequiringABattery() async throws {
        let sampler = TrayBatterySampler()
        let first = await sampler.read(includeAccessories: false, includeProcessList: true)
        let initial = try XCTUnwrap(first.processes?.first { $0.id.pid == getpid() })
        XCTAssertGreaterThan(initial.memory, 0)
        XCTAssertNil(initial.cpuPercent)
        XCTAssertNil(initial.energyWatts)

        try await Task.sleep(for: .milliseconds(1100))
        let second = await sampler.read(includeAccessories: false, includeProcessList: true)
        let measured = try XCTUnwrap(second.processes?.first { $0.id == initial.id })
        XCTAssertNotNil(measured.cpuPercent)
        XCTAssertEqual(second.telemetry.consumer?.name, TrayBatteryTelemetry.leadingConsumer(try XCTUnwrap(second.processes))?.name)

        let betweenSamples = await sampler.read(includeAccessories: false, includeProcessList: true)
        XCTAssertNil(betweenSamples.processes)
        XCTAssertEqual(betweenSamples.telemetry.consumer?.name, second.telemetry.consumer?.name)
    }

    func testBusyProcessCPUUsesHostTimebase() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
        child.standardOutput = FileHandle.nullDevice
        try child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        let sampler = TrayProcessSampler()
        _ = await sampler.sample()
        try await Task.sleep(for: .seconds(2))
        let rows = await sampler.sample()
        let row = try XCTUnwrap(rows.first { $0.id.pid == child.processIdentifier })
        let cpu = try XCTUnwrap(row.cpuPercent)
        XCTAssertGreaterThan(cpu, 10, "Un cœur occupé ne doit pas apparaître à 2 % sur Apple Silicon")
        XCTAssertLessThan(cpu, 115, "Le processus de test utilise un seul thread")
    }

    @MainActor func testQuitOwnedDisposableProcessAndRejectStaleIdentity() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["60"]
        try child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        let sampler = TrayProcessSampler()
        let snapshot = await sampler.sample()
        let row = try XCTUnwrap(snapshot.first { $0.id.pid == child.processIdentifier })
        XCTAssertTrue(row.canQuit)
        let controller = TrayProcessController()
        let stale = TrayProcess(id: .init(pid: row.id.pid, startedSeconds: row.id.startedSeconds + 1,
                                         startedMicroseconds: row.id.startedMicroseconds),
                                name: row.name, userID: row.userID, memory: row.memory, cpuPercent: row.cpuPercent, executable: row.executable)
        controller.quit(stale)
        XCTAssertTrue(child.isRunning)
        XCTAssertTrue(controller.pending.isEmpty)
        controller.quit(row)
        for _ in 0..<30 {
            if !child.isRunning { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(child.isRunning, "La demande SIGTERM doit réellement fermer le processus de test")
    }

    @MainActor func testForceQuitOwnedDisposableProcess() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["60"]
        try child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        let rows = await TrayProcessSampler().sample()
        let row = try XCTUnwrap(rows.first { $0.id.pid == child.processIdentifier })
        TrayProcessController().quit(row, force: true)
        for _ in 0..<30 {
            if !child.isRunning { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(child.isRunning)
        XCTAssertEqual(child.terminationReason, .uncaughtSignal)
        XCTAssertEqual(child.terminationStatus, SIGKILL)
    }
}
