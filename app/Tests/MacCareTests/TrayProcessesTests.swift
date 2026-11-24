import XCTest
@testable import MacCare

final class TrayProcessesTests: XCTestCase {
    func testPIDColumnAndSortUseTheLargestMemberForBackgroundApplications() throws {
        func member(_ pid: pid_t, _ path: String, _ bytes: UInt64) -> TrayProcess {
            TrayProcess(id: .init(pid: pid, startedSeconds: 1, startedMicroseconds: 0),
                        name: "node", userID: getuid(), memory: bytes, cpuPercent: 0, executable: path)
        }
        let runtime = "/tmp/Timon.app/Contents/Resources/node/node"
        let groups = HomeProcessGroup.collect([member(83445, runtime, 130), member(83450, runtime, 400),
                                               member(90_000, "/usr/bin/other", 20)])
        let group = try XCTUnwrap(groups.first { $0.name == "Timon" })
        XCTAssertNil(group.primary)
        XCTAssertEqual(group.representative.id.pid, 83450)
        XCTAssertEqual(group.memory, 530)
        XCTAssertEqual(HomeProcessSort(column: .pid, ascending: true).ordered(groups).first?.representative.id.pid, 83450)
        XCTAssertTrue(group.matches("83445"))
    }

    func testWindowServerFootprintParticipatesInNormalMemorySort() throws {
        let output = "PhysMem: 7500M used.\nPID  MEM  IDLEW\n416  605M  200\n"
        let counters = WindowServerSample.counters(in: output, pid: 416, timestamp: 1)
        let bytes = try XCTUnwrap(counters.bytes)
        XCTAssertEqual(counters.idleWakeups, 200)
        XCTAssertEqual(bytes, 605 * 1_048_576)
        XCTAssertNil(WindowServerSample.counters(in: output, pid: 123, timestamp: 1).bytes)
        XCTAssertNil(WindowServerSample.counters(in: "416 N/A 123", pid: 416, timestamp: 1).bytes)
        let ws = WindowServerSample(id: .init(pid: 416, startedSeconds: 1, startedMicroseconds: 0),
                                    userID: 88, cpuSeconds: nil, timestamp: 1,
                                    counters: counters).process(after: nil, maximumInterval: 10)
        let app = TrayProcess(id: .init(pid: 83450, startedSeconds: 1, startedMicroseconds: 0),
                              name: "Timon", userID: getuid(), memory: 579_000_000, cpuPercent: 0, executable: "")
        XCTAssertFalse(ws.canQuit)
        XCTAssertEqual(HomeProcessSort().ordered(HomeProcessGroup.collect([ws, app])).map(\.name), ["WindowServer", "Timon"])
        XCTAssertEqual(HomeProcessSort(column: .memory, ascending: true).ordered(HomeProcessGroup.collect([ws, app])).first?.name, "Timon")
    }

    func testWindowServerUsesCPUTimeAcrossSamplesOfTheSameProcess() throws {
        XCTAssertEqual(WindowServerSample.seconds(" 2496:50.77\n"), 149810.77)
        XCTAssertEqual(WindowServerSample.seconds("1:02:03.50"), 3723.5)
        XCTAssertNil(WindowServerSample.seconds("—"))
        func sample(_ start: UInt64, _ time: Double, _ cpu: Double?) -> WindowServerSample {
            .init(id: .init(pid: 416, startedSeconds: start, startedMicroseconds: 9),
                  userID: 88, cpuSeconds: cpu, timestamp: time,
                  counters: .init(bytes: nil, idleWakeups: UInt64(40 * time), timestamp: time))
        }
        let first = sample(10, 2, 174), second = sample(10, 4, 175)
        let row = second.process(after: first, maximumInterval: 10)
        XCTAssertEqual(row.cpuPercent, 50)
        XCTAssertEqual(row.idleWakeupsPerSecond, 40)
        XCTAssertEqual(try XCTUnwrap(ProcessEnergyScore([row])).value, 10.4, accuracy: 0.0001)
        XCTAssertNil(second.process(after: sample(9, 2, 174), maximumInterval: 10).idleWakeupsPerSecond)
        XCTAssertNil(row.memory)
        XCTAssertNil(row.energyWatts)
        XCTAssertFalse(row.canQuit)
        XCTAssertNil(first.process(after: nil, maximumInterval: 10).cpuPercent)
        XCTAssertNil(second.process(after: sample(9, 2, 174), maximumInterval: 10).cpuPercent)
        XCTAssertNil(second.process(after: first, maximumInterval: 1).cpuPercent)
        XCTAssertNil(second.process(after: sample(10, 2, nil), maximumInterval: 10).cpuPercent)
        let measured = TrayProcess(id: .init(pid: 100, startedSeconds: 1, startedMicroseconds: 0),
                                   name: "Autre", userID: 501, memory: 0, cpuPercent: 2, executable: "")
        let groups = HomeProcessGroup.collect([row, measured])
        XCTAssertEqual(HomeProcessMetric.memory(groups.first { $0.name == "WindowServer" }?.memory), "—")
        for ascending in [true, false] {
            XCTAssertEqual(HomeProcessSort(column: .memory, ascending: ascending).ordered(groups).last?.name, "WindowServer")
        }
        XCTAssertEqual(HomeProcessSort(column: .cpu).ordered(groups).first?.name, "WindowServer")
    }

    @MainActor func testProcessDetailOpensWithInspectionAndCancelsPendingOpen() async throws {
        let rows = await TrayProcessSampler().sample()
        let process = try XCTUnwrap(rows.first { $0.id.pid == getpid() })
        let group = try XCTUnwrap(HomeProcessGroup.collect([process]).first)
        let presentation = HomeProcessPresentation(), controller = TrayProcessController()
        presentation.open(group, member: process, controller: controller)
        XCTAssertNil(presentation.presented)
        presentation.close()
        presentation.open(group, member: process, controller: controller)
        for _ in 0..<100 where presentation.presented == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        let selection = try XCTUnwrap(presentation.presented?.selection)
        XCTAssertEqual(selection.id, process.id)
        XCTAssertNotNil(selection.inspection?.threads)
        presentation.close()
        presentation.open(group, member: process, controller: controller)
        presentation.close()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(presentation.presented)
    }

    func testCPUWarningAndCriticalThresholdsAreStrict() {
        XCTAssertEqual(ProcessCPULevel(nil), .normal)
        XCTAssertEqual(ProcessCPULevel(40), .normal)
        XCTAssertEqual(ProcessCPULevel(40.1), .elevated)
        XCTAssertEqual(ProcessCPULevel(80), .elevated)
        XCTAssertEqual(ProcessCPULevel(80.1), .critical)
        XCTAssertEqual(ProcessCPULevel(220), .critical)
    }

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
        let groups = HomeProcessGroup.collect(rows.reversed())
        let leaders = HomeProcessSort.highCPUApplications(in: groups)
        XCTAssertEqual(leaders.map(\.name), ["A", "C", "D"])
        XCTAssertEqual(leaders.map(\.cpu), [90, 70, 70])
        XCTAssertTrue(HomeProcessSort.highCPUApplications(in: HomeProcessGroup.collect(Array(rows.suffix(3)))).isEmpty)
    }

    func testHomeGroupsHelpersAndKeepsProcessesFromOtherOwnersSeparate() throws {
        let app = "/Applications/Code.app", helper = "/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"
        func process(_ pid: pid_t, _ uid: uid_t, _ path: String, _ wakes: Double?) -> TrayProcess {
            TrayProcess(id: .init(pid: pid, startedSeconds: 1, startedMicroseconds: 0),
                        name: path.hasSuffix("Helper") ? "Renderer" : "Code", userID: uid, memory: 100,
                        cpuPercent: wakes == nil ? nil : 25, executable: path, idleWakeupsPerSecond: wakes)
        }
        let rows = [process(12, 501, app + "/Contents/MacOS/Code", 16),
                    process(13, 501, app + helper, 4), process(14, 501, app + helper, nil),
                    process(20, 502, app + helper, nil), process(21, 501, "/Volumes/Test/Code.app" + helper, nil),
                    process(22, 501, "/usr/bin/sleep", nil)]
        let apps: [pid_t: HomeProcessGroup.Application] = [12: .init(url: URL(fileURLWithPath: app), name: "Code")]
        let groups = HomeProcessGroup.collect(rows, registered: apps)
        XCTAssertEqual(groups.count, 4)
        let code = try XCTUnwrap(groups.first { $0.primary?.id.pid == 12 })
        XCTAssertEqual(code.members.count, 3)
        XCTAssertEqual(code.memory, 300)
        XCTAssertEqual(code.cpu, 50)
        let score = try XCTUnwrap(code.energyScore)
        XCTAssertEqual(score.value, 10.2, accuracy: 0.00001)
        XCTAssertTrue(score.isLowerBound)
        XCTAssertTrue(code.matches("Renderer"))
        XCTAssertTrue(code.matches("14"))
        XCTAssertFalse(code.matches("sleep"))
        XCTAssertEqual(HomeProcessSort(column: .energy).ordered(groups).first?.id, code.id)
        let helperOnly = try XCTUnwrap(groups.first { $0.members[0].id.pid == 20 })
        XCTAssertNil(helperOnly.primary)
        XCTAssertNil(helperOnly.energyScore)
        XCTAssertNil(helperOnly.cpu)
    }

    func testEnergyScoreScaleAndUnavailableSamples() throws {
        func row(_ cpu: Double?, _ wakes: Double?) -> TrayProcess {
            .init(id: .init(pid: 1, startedSeconds: 1, startedMicroseconds: 0),
                  name: "Test", userID: 501, memory: 0, cpuPercent: cpu, executable: "",
                  idleWakeupsPerSecond: wakes)
        }
        XCTAssertNil(ProcessEnergyScore([row(nil, nil)]))
        XCTAssertEqual(ProcessEnergyScore([row(0, 0)])?.label, "0/20")
        let half = try XCTUnwrap(ProcessEnergyScore([row(45, 100)]))
        XCTAssertEqual(half.number, "10")
        XCTAssertEqual(half.label, "10/20")
        XCTAssertFalse(half.isLowerBound)
        XCTAssertEqual(ProcessEnergyScore([row(25, nil)])?.label, "≥ 5/20")
        XCTAssertEqual(ProcessEnergyScore([row(80, 0), row(50, nil)])?.label, "20/20")
        XCTAssertTrue(ProcessEnergyScore.help.contains("sur 20"))
    }

    func testDetailsReadLiveIdentityAndRejectRecycledPID() async throws {
        let sample = await TrayProcessSampler().sample()
        let current = try XCTUnwrap(sample.first { $0.id.pid == getpid() })
        let details = try XCTUnwrap(HomeProcessInspection.read(current))
        XCTAssertGreaterThan(details.threads, 0)
        XCTAssertGreaterThan(try XCTUnwrap(details.files), 0)
        XCTAssertNotNil(details.directory)
        XCTAssertNotNil(details.diskRead)
        let stale = TrayProcess(id: .init(pid: getpid(), startedSeconds: 1, startedMicroseconds: 0),
                               name: current.name, userID: current.userID, memory: 0, cpuPercent: nil, executable: current.executable)
        XCTAssertNil(HomeProcessInspection.read(stale))
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
        XCTAssertGreaterThan(try XCTUnwrap(own.memory), 0)
        XCTAssertNotNil(own.cpuPercent)
        XCTAssertGreaterThanOrEqual(own.cpuPercent ?? -1, 0)
    }

    func testDashboardReceivesOnlyFreshProcessSamplesWithoutRequiringABattery() async throws {
        let sampler = TrayBatterySampler()
        let first = await sampler.read(includeAccessories: false, includeProcessList: true)
        let initial = try XCTUnwrap(first.processes?.first { $0.id.pid == getpid() })
        XCTAssertGreaterThan(try XCTUnwrap(initial.memory), 0)
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
