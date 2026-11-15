import Foundation
import Darwin

public struct BatteryHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let percent: Int
    public let temperature: Double?
    public let health: Int?
    public let cycles: Int?
    public let onAC: Bool
    public let charging: Bool
    public init?(snapshot: BatterySnapshot, date: Date) {
        guard snapshot.present, let percent = snapshot.percent, (0...100).contains(percent), date.timeIntervalSince1970.isFinite else { return nil }
        self.date = date; self.percent = percent; temperature = snapshot.temperature
        health = snapshot.healthPercent; cycles = snapshot.cycles; onAC = snapshot.onAC; charging = snapshot.charging
    }
}

/// Local-only bounded history. Disk IO is isolated from the UI; timestamps are
/// observed samples, never reconstructed historical estimates.
public actor BatteryHistoryStore {
    private let directory: URL
    private var entries: [BatteryHistoryEntry]?
    private var historyRevision: HistoryRevision?
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacCare/Battery", isDirectory: true)
    }
    public func load(now: Date = .now) throws -> [BatteryHistoryEntry] {
        let file = directory.appendingPathComponent("history.json")
        guard let revision = try HistoryRevision.read(file) else {
            entries = nil; historyRevision = nil
            return []
        }
        if entries == nil || historyRevision != revision {
            let decoded = try JSONDecoder().decode([BatteryHistoryEntry].self, from: Data(contentsOf: file))
            entries = decoded.filter { (0...100).contains($0.percent) }.sorted { $0.date < $1.date }
            historyRevision = revision
        }
        let cutoff = now.addingTimeInterval(-30 * 86400)
        // Reapply the time window even when the file did not change (including clock rollback).
        return Array((entries ?? []).filter { $0.date >= cutoff && $0.date <= now }.suffix(10_000))
    }
    @discardableResult public func append(snapshot: BatterySnapshot, at date: Date = .now) throws -> [BatteryHistoryEntry] {
        try withFileLock("history.lock") {
            // The file revision is checked under the interprocess lock. An unchanged history
            // needs no JSON decoding; another app instance's writes are still merged.
            return try appendLocked(snapshot: snapshot, at: date)
        }
    }
    private func appendLocked(snapshot: BatterySnapshot, at date: Date) throws -> [BatteryHistoryEntry] {
        var values = try load(now: date)
        guard let entry = BatteryHistoryEntry(snapshot: snapshot, date: date) else { return values }
        if let last = values.last {
            guard date > last.date else { return values }
            if date.timeIntervalSince(last.date) < 300 && last.percent == entry.percent && last.onAC == entry.onAC && last.charging == entry.charging { return values }
        }
        let cutoff = date.addingTimeInterval(-30 * 86400)
        values = values.filter { $0.date >= cutoff }; values.append(entry)
        values = Array(values.suffix(10_000))
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard (try fm.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType) == .typeDirectory else { throw HistoryError() }
        let file = directory.appendingPathComponent("history.json")
        if fm.fileExists(atPath: file.path), (try fm.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType) != .typeRegular { throw HistoryError() }
        try JSONEncoder().encode(values).write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        entries = values
        historyRevision = try HistoryRevision.read(file)
        return values
    }

    private struct HistoryRevision: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        static func read(_ file: URL) throws -> Self? {
            var info = stat()
            guard lstat(file.path, &info) == 0 else {
                if errno == ENOENT { return nil }
                throw HistoryError()
            }
            guard info.st_mode & S_IFMT == S_IFREG, info.st_size <= 2_500_000 else { throw HistoryError() }
            return .init(device: info.st_dev, inode: info.st_ino, size: info.st_size,
                         modifiedSeconds: info.st_mtimespec.tv_sec, modifiedNanoseconds: info.st_mtimespec.tv_nsec,
                         changedSeconds: info.st_ctimespec.tv_sec, changedNanoseconds: info.st_ctimespec.tv_nsec)
        }
    }
    public func loadSchedules() throws -> [BatterySchedule] {
        let file = directory.appendingPathComponent("schedules.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              ((attrs[.size] as? NSNumber)?.intValue ?? Int.max) <= 256_000 else { throw HistoryError() }
        let values = try JSONDecoder().decode([BatterySchedule].self, from: Data(contentsOf: file))
        guard values.count <= 100, values.allSatisfy({ $0.isValid }), Set(values.map(\.id)).count == values.count else { throw HistoryError() }
        return values
    }
    public func saveSchedules(_ values: [BatterySchedule]) throws {
        try withFileLock("schedules.lock") { try writeSchedules(values) }
    }
    public func upsertSchedule(_ schedule: BatterySchedule) throws -> [BatterySchedule] {
        try withFileLock("schedules.lock") {
            var values = try loadSchedules()
            var incoming = schedule
            if let index = values.firstIndex(where: { $0.id == schedule.id }) {
                incoming.preserveProgress(from: values[index]); values[index] = incoming
            } else { values.append(incoming) }
            try writeSchedules(values)
            return values
        }
    }
    public func deleteSchedule(_ id: UUID) throws -> [BatterySchedule] {
        try withFileLock("schedules.lock") {
            let values = try loadSchedules().filter { $0.id != id }
            try writeSchedules(values)
            return values
        }
    }
    public func claimSchedule(_ id: UUID, at now: Date) throws -> (schedules: [BatterySchedule], claim: BatterySchedule.Claim, schedule: BatterySchedule?) {
        try withFileLock("schedules.lock") {
            var values = try loadSchedules()
            guard let index = values.firstIndex(where: { $0.id == id }) else { return (values, .notDue, nil) }
            let claim = values[index].claim(at: now)
            if claim != .notDue { try writeSchedules(values) }
            return (values, claim, values[index])
        }
    }
    private func withFileLock<T>(_ name: String, operation: () throws -> T) throws -> T {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard try fm.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else { throw HistoryError() }
        let fd = open(directory.appendingPathComponent(name).path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw HistoryError() }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw HistoryError() }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }
    private func writeSchedules(_ values: [BatterySchedule]) throws {
        guard values.count <= 100, values.allSatisfy({ $0.isValid }), Set(values.map(\.id)).count == values.count else { throw HistoryError() }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard try fm.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else { throw HistoryError() }
        let file = directory.appendingPathComponent("schedules.json")
        if fm.fileExists(atPath: file.path), try fm.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType != .typeRegular { throw HistoryError() }
        try JSONEncoder().encode(values).write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        // Durable claim before a hardware action; a crash must not repeat a due cycle.
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw HistoryError() }
        let saved = fsync(descriptor); close(descriptor)
        guard saved == 0 else { throw HistoryError() }
        let parent = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw HistoryError() }
        let synced = fsync(parent); close(parent)
        guard synced == 0 else { throw HistoryError() }
    }
    private struct HistoryError: LocalizedError {
        var errorDescription: String? { "L’historique local de batterie ne peut pas être lu ou enregistré." }
    }
}
