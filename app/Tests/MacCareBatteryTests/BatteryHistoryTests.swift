import Foundation
import Testing
import MacCareBattery

struct BatteryHistoryTests {
    @Test func readingHistorySeesChangesFromAnotherInstance() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = BatteryHistoryStore(directory: directory), second = BatteryHistoryStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(try await first.load(now: now).isEmpty)
        try await second.append(snapshot: .init(percent: 80, onAC: true), at: now)
        #expect(try await first.load(now: now).map(\.percent) == [80])
        try await first.append(snapshot: .init(percent: 79, onAC: false), at: now.addingTimeInterval(15))
        #expect(try await second.load(now: now.addingTimeInterval(15)).map(\.percent) == [80, 79])
    }

    @Test func cachedHistoryStillExpiresAndHonorsClockChanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BatteryHistoryStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await store.append(snapshot: .init(percent: 80), at: now)
        #expect(try await store.load(now: now.addingTimeInterval(-1)).isEmpty)
        #expect(try await store.load(now: now).count == 1)
        #expect(try await store.load(now: now.addingTimeInterval(31 * 86400)).isEmpty)
    }

    @Test func unchangedSamplesPreserveLargeHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = BatterySnapshot(percent: 80, onAC: true)
        let entries = try (0..<10_000).map { index in
            try #require(BatteryHistoryEntry(snapshot: snapshot, date: now.addingTimeInterval(Double(index - 10_000) * 180)))
        }
        let file = directory.appendingPathComponent("history.json")
        let encoded = try JSONEncoder().encode(entries)
        try encoded.write(to: file)
        let store = BatteryHistoryStore(directory: directory)
        #expect(try await store.load(now: now).count == 10_000)
        let start = ContinuousClock.now
        for _ in 0..<60 {
            #expect(try await store.append(snapshot: snapshot, at: now).count == 10_000)
        }
        print("HISTORY_BENCHMARK 60 unchanged samples / 10000 entries:", start.duration(to: .now))
        #expect(try Data(contentsOf: file) == encoded)
    }

    @Test(arguments: [true, false])
    func cachedHistoryDetectsSameSizeReplacement(atomic: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BatteryHistoryStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await store.append(snapshot: .init(percent: 80), at: now)
        let file = directory.appendingPathComponent("history.json")
        let previous = try FileManager.default.attributesOfItem(atPath: file.path)
        let replacement = try #require(BatteryHistoryEntry(snapshot: .init(percent: 79), date: now))
        let data = try JSONEncoder().encode([replacement])
        #expect(data.count == (previous[.size] as? NSNumber)?.intValue)
        try data.write(to: file, options: atomic ? .atomic : [])
        // Modification time and length alone are insufficient to identify a revision.
        try FileManager.default.setAttributes([.modificationDate: try #require(previous[.modificationDate])], ofItemAtPath: file.path)
        #expect(try await store.load(now: now).map(\.percent) == [79])
        #expect(try await store.append(snapshot: .init(percent: 78), at: now.addingTimeInterval(15)).map(\.percent) == [79, 78])
    }

    @Test func cachedHistoryDoesNotHideRemovalOrCorruption() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BatteryHistoryStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await store.append(snapshot: .init(percent: 80), at: now)
        let file = directory.appendingPathComponent("history.json")
        try Data("invalid JSON".utf8).write(to: file, options: .atomic)
        await #expect(throws: (any Error).self) { try await store.load(now: now) }
        try FileManager.default.removeItem(at: file)
        #expect(try await store.load(now: now).isEmpty)
    }

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
