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
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacCare/Battery", isDirectory: true)
    }
    public func load(now: Date = .now) throws -> [BatteryHistoryEntry] {
        if let entries { return entries }
        let file = directory.appendingPathComponent("history.json")
        guard FileManager.default.fileExists(atPath: file.path) else { entries = []; return [] }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 2_500_000 else {
            throw HistoryError()
        }
        let decoded = try JSONDecoder().decode([BatteryHistoryEntry].self, from: Data(contentsOf: file))
        let cutoff = now.addingTimeInterval(-30 * 86400)
        let valid = decoded.filter { $0.date >= cutoff && $0.date <= now && (0...100).contains($0.percent) }
        entries = Array(valid.sorted { $0.date < $1.date }.suffix(10_000))
        return entries ?? []
    }
    @discardableResult public func append(snapshot: BatterySnapshot, at date: Date = .now) throws -> [BatteryHistoryEntry] {
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
        return values
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
