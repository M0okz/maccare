import XCTest
@testable import MacCare

final class TrayProcessesTests: XCTestCase {
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
