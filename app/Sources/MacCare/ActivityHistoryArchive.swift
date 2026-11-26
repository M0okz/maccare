import CryptoKit
import CSQLite
import Darwin
import Foundation
import OSLog

enum ActivitySeries: Int, CaseIterable, Sendable {
    case cpu, gpu, memory, received, sent
}

extension TrayMetrics.Network {
    var historyIdentity: String { "\(kind.rawValue):\(interface):\(address ?? "")" }

    // Store only a stable fingerprint of the interface, never its address.
    var historySource: Int64 {
        SHA256.hash(data: Data(historyIdentity.utf8)).prefix(8).reduce(Int64(0)) { ($0 << 8) | Int64($1) }
    }
}

private struct ActivityBucket: Hashable {
    let series: ActivitySeries
    let source: Int64
    let session: Int64
    let start: Int64
}

private struct ActivityAggregate {
    var time: Double
    var sum: Double
    var peak: Double
    var count: Int

    mutating func add(_ value: Double, at time: Double) {
        self.time = max(self.time, time)
        sum += value
        peak = max(peak, value)
        count += 1
    }
}

/// All disk access and aggregation for the archive run on this actor.
/// Five-second rows and minute summaries commit in the same transaction.
actor ActivityHistoryArchive {
    static let retention: TimeInterval = 30 * 86400
    static let logger = Logger(subsystem: "org.maccare.app", category: "ActivityHistory")
    static var applicationStore: ActivityHistoryArchive {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = AppBuildIdentity.isDevelopment ? "MacCare Dev" : "MacCare"
        return ActivityHistoryArchive(url: base.appendingPathComponent(folder).appendingPathComponent("Activity/history.sqlite"))
    }

    let url: URL
    private var pending: [ActivityBucket: ActivityAggregate] = [:]
    private var lastAttempt: TimeInterval?
    private var network: (identity: String, source: Int64)?

    init(url: URL) { self.url = url }

    @discardableResult
    func append(_ sample: TrayMetrics, time: TimeInterval, session: Int64) -> Bool {
        let start = Int64(floor(time / 5)) * 5
        func add(_ series: ActivitySeries, _ value: Double?, source: Int64 = 0) {
            guard let value, value.isFinite, value >= 0 else { return }
            let key = ActivityBucket(series: series, source: source, session: session, start: start)
            if pending[key] == nil {
                pending[key] = .init(time: time, sum: value, peak: value, count: 1)
            } else {
                pending[key]?.add(value, at: time)
            }
        }
        add(.cpu, sample.cpu?.used.mapToFraction)
        add(.memory, sample.memory?.fraction)
        if let gpu = sample.gpu { add(.gpu, gpu.fraction?.mapToFraction, source: Int64(bitPattern: gpu.id)) }
        if let wifi = sample.wifi, wifi.connected, let rx = wifi.received, let tx = wifi.sent,
           rx.isFinite, rx >= 0, tx.isFinite, tx >= 0 {
            if network?.identity != wifi.historyIdentity { network = (wifi.historyIdentity, wifi.historySource) }
            if let source = network?.source {
                add(.received, rx, source: source)
                add(.sent, tx, source: source)
            }
        }
        if let lastAttempt, time >= lastAttempt, time - lastAttempt < 60 { return false }
        let first = lastAttempt == nil
        lastAttempt = time
        guard !first else { return false }
        do { try flush(now: time); return true }
        catch {
            // Keep a bounded retry buffer even if the volume remains unwritable.
            pending = pending.filter { Double($0.key.start) >= time - 3600 }
            Self.logger.error("Écriture de l’historique différée : \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func flush(now: TimeInterval) throws {
        guard !pending.isEmpty else { return }
        let db = try ActivityDatabase(url)
        try db.exec("BEGIN IMMEDIATE")
        do {
            let insert = try db.statement("""
                INSERT INTO history (step,series,bucket,session,source,time,total,peak,n)
                VALUES (?,?,?,?,?,?,?,?,?)
                ON CONFLICT(step,series,bucket,session,source) DO UPDATE SET
                    time=max(time,excluded.time), total=total+excluded.total,
                    peak=max(peak,excluded.peak), n=n+excluded.n
                """)
            defer { sqlite3_finalize(insert) }
            for (key, aggregate) in pending {
                for step: Int64 in [5, 60] {
                    let bucket = key.start / step * step
                    sqlite3_reset(insert)
                    for (index, value) in [step, Int64(key.series.rawValue), bucket, key.session, key.source].enumerated() {
                        sqlite3_bind_int64(insert, Int32(index + 1), value)
                    }
                    sqlite3_bind_double(insert, 6, aggregate.time)
                    sqlite3_bind_double(insert, 7, aggregate.sum)
                    sqlite3_bind_double(insert, 8, aggregate.peak)
                    sqlite3_bind_int64(insert, 9, Int64(aggregate.count))
                    try db.check(sqlite3_step(insert), expected: SQLITE_DONE)
                }
            }
            try db.prune(now: now)
            try db.exec("COMMIT")
            pending.removeAll(keepingCapacity: true)
        } catch {
            try? db.exec("ROLLBACK")
            throw error
        }
    }

    func recent(now: TimeInterval) throws -> [ActivitySeries: [TrayHistoryPoint]] {
        let db = try ActivityDatabase(url)
        try db.prune(now: now)
        var result: [ActivitySeries: [TrayHistoryPoint]] = [:]
        for series in ActivitySeries.allCases {
            result[series] = try db.points(series: series, step: 5, duration: 3600, end: now)
        }
        return result
    }

    func trend(_ series: ActivitySeries, duration: TimeInterval, end: TimeInterval) throws -> [TrayHistoryPoint] {
        let db = try ActivityDatabase(url)
        return try db.points(series: series, step: 60, duration: min(duration, Self.retention), end: end)
    }
}

private extension Double {
    var mapToFraction: Double { isFinite ? min(1, max(0, self)) : self }
}

private final class ActivityDatabase {
    private let handle: OpaquePointer
    init(_ url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var db: OpaquePointer?
        // macOS places temporary and some user directories below symlinked ancestors.
        // Resolve the directory only, keeping NOFOLLOW protection on the database itself.
        guard let resolved = realpath(directory.path, nil) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { free(resolved) }
        let path = String(cString: resolved) + "/" + url.lastPathComponent
        let status = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOFOLLOW, nil)
        guard status == SQLITE_OK, let db else {
            let code = db.map(sqlite3_extended_errcode) ?? status
            sqlite3_close(db)
            throw NSError(domain: "SQLite", code: Int(code),
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errstr(code))])
        }
        handle = db
        sqlite3_busy_timeout(db, 1000)
        try exec("""
            CREATE TABLE IF NOT EXISTS history(
                step INTEGER, series INTEGER, bucket INTEGER, session INTEGER, source INTEGER,
                time REAL NOT NULL, total REAL NOT NULL, peak REAL NOT NULL, n INTEGER NOT NULL,
                PRIMARY KEY(step,series,bucket,session,source)) WITHOUT ROWID
            """)
    }
    deinit { sqlite3_close(handle) }

    func check(_ result: Int32, expected: Int32 = SQLITE_OK) throws {
        guard result == expected else {
            throw NSError(domain: "SQLite", code: Int(result),
                          userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle))])
        }
    }
    func exec(_ sql: String) throws { try check(sqlite3_exec(handle, sql, nil, nil, nil)) }
    func statement(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(handle, sql, -1, &statement, nil))
        guard let statement else { throw NSError(domain: "SQLite", code: Int(SQLITE_ERROR)) }
        return statement
    }

    func prune(now: TimeInterval) throws {
        // Match the primary key prefix for five small range deletes per resolution.
        for series in ActivitySeries.allCases {
            for (step, age) in [(5, 3600.0), (60, ActivityHistoryArchive.retention)] {
                try exec("DELETE FROM history WHERE step=\(step) AND series=\(series.rawValue) AND bucket<\(Int64(now-age)-Int64(step))")
            }
        }
    }

    func points(series: ActivitySeries, step: Int, duration: TimeInterval, end: TimeInterval) throws -> [TrayHistoryPoint] {
        let query = try statement("""
            SELECT time,total,peak,n,session,source FROM history
            WHERE step=? AND series=? AND bucket BETWEEN ? AND ? AND time BETWEEN ? AND ?
            ORDER BY bucket,time
            """)
        defer { sqlite3_finalize(query) }
        sqlite3_bind_int(query, 1, Int32(step))
        sqlite3_bind_int(query, 2, Int32(series.rawValue))
        sqlite3_bind_int64(query, 3, Int64(end-duration)-Int64(step))
        sqlite3_bind_int64(query, 4, Int64(end))
        sqlite3_bind_double(query, 5, end-duration)
        sqlite3_bind_double(query, 6, end)
        var points: [TrayHistoryPoint] = []
        let width = max(60, ceil(duration / 480 / 60) * 60)
        var previousGroup: Double?
        var status = sqlite3_step(query)
        while status == SQLITE_ROW {
            let time = sqlite3_column_double(query, 0)
            let total = sqlite3_column_double(query, 1)
            let peak = sqlite3_column_double(query, 2)
            let count = Int(sqlite3_column_int64(query, 3))
            let session = sqlite3_column_int64(query, 4)
            let source = sqlite3_column_int64(query, 5)
            let group = floor(time / width)
            let last = points.last
            let starts = last.map { $0.session != session || $0.source != source || time - $0.time > Double(step) * 3 } ?? true
            if step == 60, !starts, previousGroup == group, let last {
                let n = last.count + count
                points[points.count-1] = .init(time: time, value: (last.value * Double(last.count) + total) / Double(n),
                    peak: max(last.peak, peak), count: n, session: session, source: source, startsSegment: last.startsSegment)
            } else {
                points.append(.init(time: time, value: total / Double(count), peak: peak, count: count,
                                    session: session, source: source, startsSegment: starts))
            }
            previousGroup = group
            status = sqlite3_step(query)
        }
        try check(status, expected: SQLITE_DONE)
        return points
    }
}
