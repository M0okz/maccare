import Foundation
import Testing
import MacCareBattery

struct BatteryHistoryTests {
    @Test func historyIsRealBoundedAndPersistsAcrossInstances() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BatteryHistoryStore(directory: directory), now = Date()
        #expect(try await store.load(now: now).isEmpty)
        let snapshot = BatterySnapshot(percent: 80, onAC: true, temperature: 28)
        #expect(try await store.append(snapshot: snapshot, at: now).count == 1)
        #expect(try await store.append(snapshot: snapshot, at: now.addingTimeInterval(30)).count == 1)
        #expect(try await store.append(snapshot: .init(percent: 79, onAC: false, temperature: 28), at: now.addingTimeInterval(60)).count == 2)
        let restored = BatteryHistoryStore(directory: directory)
        #expect(try await restored.load(now: now.addingTimeInterval(60)).count == 2)
        let later = now.addingTimeInterval(31 * 86400)
        #expect(try await store.append(snapshot: snapshot, at: later).count == 1)
        #expect(try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("history.json").path)[.posixPermissions] as? Int == 0o600)
    }
    @Test func unknownPercentageNeverFabricatesHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BatteryHistoryStore(directory: directory)
        #expect(try await store.append(snapshot: .init()).isEmpty)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.json").path) == false)
    }
    @Test func durableScheduleCheckpointPreventsReplay() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BatteryHistoryStore(directory: directory), now = Date()
        var schedule = BatterySchedule(name: "Une fois", action: .topUp, recurrence: .once, firstRun: now)
        #expect(schedule.claim(at: now) == .run)
        try await store.saveSchedules([schedule])
        let restored = BatteryHistoryStore(directory: directory)
        var values = try await restored.loadSchedules()
        #expect(values.count == 1)
        #expect(values[0].claim(at: now) == .notDue)
        #expect(values[0].enabled == false)
    }

    @Test func concurrentInstancesCannotClaimTheSameCycleTwice() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = BatteryHistoryStore(directory: directory), second = BatteryHistoryStore(directory: directory)
        let now = Date(), schedule = BatterySchedule(name: "Cycle", action: .calibrate, recurrence: .once, firstRun: .now)
        try await first.saveSchedules([schedule])
        async let a = first.claimSchedule(schedule.id, at: now.addingTimeInterval(1))
        async let b = second.claimSchedule(schedule.id, at: now.addingTimeInterval(1))
        let results = try await (a, b)
        let runs = (results.0.claim == .run ? 1 : 0) + (results.1.claim == .run ? 1 : 0)
        #expect(runs == 1)
        _ = try await first.upsertSchedule(schedule)
        #expect(try await second.claimSchedule(schedule.id, at: now.addingTimeInterval(2)).claim == .notDue)
    }

}
