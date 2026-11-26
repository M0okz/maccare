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
    private var pending: [ActivityBucket: TrayHistoryPoint] = [:]
    private var continuity: [ActivitySeries: ActivitySeriesContinuity] = [:]
    private var lastAttempt: TimeInterval?
    private var network: (identity: String, source: Int64)?

    init(url: URL) { self.url = url }

    @discardableResult
    func append(_ sample: TrayMetrics, time: TimeInterval, session: Int64) -> Bool {
        let start = Int64(floor(time / 5)) * 5
        func add(_ series: ActivitySeries, _ value: Double?, source: Int64 = 0) {
            guard let point = continuity[series, default: .init()].observe(value, time: time, uptime: sample.sampledAt,
                                                                           session: session, source: source) else { return }
            let key = ActivityBucket(series: series, source: source, session: point.session, start: start)
            pending[key] = pending[key]?.merging(point) ?? point
        }
        add(.cpu, sample.cpu?.used.mapToFraction)
        add(.memory, sample.memory?.fraction)
        add(.gpu, sample.gpu?.fraction?.mapToFraction, source: Int64(bitPattern: sample.gpu?.id ?? 0))
        if let wifi = sample.wifi, wifi.connected {
            if network?.identity != wifi.historyIdentity { network = (wifi.historyIdentity, wifi.historySource) }
            let source = network?.source ?? 0
            add(.received, wifi.received, source: source)
            add(.sent, wifi.sent, source: source)
        } else {
            add(.received, nil)
            add(.sent, nil)
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
                INSERT INTO history (step,series,bucket,session,source,time,total,peak,n,seconds,integral,peak_time)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(step,series,bucket,session,source) DO UPDATE SET
                    time=max(time,excluded.time), total=total+excluded.total,
                    peak_time=CASE WHEN excluded.peak>peak THEN excluded.peak_time
                                   WHEN excluded.peak<peak THEN peak_time
                                   ELSE coalesce(min(peak_time,excluded.peak_time),peak_time,excluded.peak_time) END,
                    peak=max(peak,excluded.peak), n=n+excluded.n,
                    seconds=seconds+excluded.seconds, integral=integral+excluded.integral
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
                    sqlite3_bind_double(insert, 7, aggregate.value * Double(aggregate.count))
                    sqlite3_bind_double(insert, 8, aggregate.peak)
                    sqlite3_bind_int64(insert, 9, Int64(aggregate.count))
                    sqlite3_bind_double(insert, 10, aggregate.seconds)
                    sqlite3_bind_double(insert, 11, aggregate.value * aggregate.seconds)
                    if let time = aggregate.peakTime { sqlite3_bind_double(insert, 12, time) }
                    else { sqlite3_bind_null(insert, 12) }
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
        try migrate()
    }

    private func schemaVersion() throws -> Int32 {
        let version = try statement("PRAGMA user_version")
        defer { sqlite3_finalize(version) }
        try check(sqlite3_step(version), expected: SQLITE_ROW)
        return sqlite3_column_int(version, 0)
    }

    private func migrate() throws {
        guard try schemaVersion() == 0 else { return }
        try exec("BEGIN IMMEDIATE")
        do {
            if try schemaVersion() == 0 {
                try exec("""
                    CREATE TABLE IF NOT EXISTS history(
                        step INTEGER, series INTEGER, bucket INTEGER, session INTEGER, source INTEGER,
                        time REAL NOT NULL, total REAL NOT NULL, peak REAL NOT NULL, n INTEGER NOT NULL,
                        PRIMARY KEY(step,series,bucket,session,source)) WITHOUT ROWID;
                    ALTER TABLE history ADD COLUMN seconds REAL;
                    ALTER TABLE history ADD COLUMN integral REAL;
                    ALTER TABLE history ADD COLUMN peak_time REAL;
                    PRAGMA user_version=1;
                    """)
            }
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
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
            SELECT time,total,peak,n,session,source,seconds,integral,peak_time FROM history
            WHERE step=? AND series=? AND bucket BETWEEN ? AND ? AND time BETWEEN ? AND ?
            ORDER BY bucket
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
        // Keep the leading partial minute separate. Its peak can predate the requested
        // window and must not hide a smaller, in-range peak during downsampling.
        let firstCompleteMinute = ceil((end - duration) / 60) * 60
        var previousGroup: Double?
        // SQLite scans the existing (step, series, bucket, ...) primary key.
        // Only a bucket containing several segments needs a secondary time sort.
        var tiedRows: [TrayHistoryPoint] = []
        var currentBucket: Double?
        func emitBucket() {
            if tiedRows.count > 1 { tiedRows.sort { $0.time < $1.time } }
            for var point in tiedRows {
                let group = floor(point.time / width)
                let last = points.last
                point.startsSegment = last.map { $0.session != point.session || $0.source != point.source
                    || point.time - $0.time > Double(step) * 3 } ?? true
                if step == 60, !point.startsSegment, previousGroup == group, let last, last.time >= firstCompleteMinute {
                    points[points.count - 1] = last.merging(point)
                } else {
                    points.append(point)
                }
                previousGroup = group
            }
            tiedRows.removeAll(keepingCapacity: true)
        }
        var status = sqlite3_step(query)
        while status == SQLITE_ROW {
            let time = sqlite3_column_double(query, 0)
            let total = sqlite3_column_double(query, 1)
            let peak = sqlite3_column_double(query, 2)
            let count = Int(sqlite3_column_int64(query, 3))
            let session = sqlite3_column_int64(query, 4)
            let source = sqlite3_column_int64(query, 5)
            let bucket = floor(time / Double(step))
            if bucket != currentBucket { emitBucket(); currentBucket = bucket }
            // Legacy rows have neither measured duration nor the instant of their peak.
            // Cap their estimated weight at one bucket and one background interval per reading.
            let legacy = sqlite3_column_type(query, 6) == SQLITE_NULL
            let seconds = legacy ? min(Double(step), Double(count) * 5) : sqlite3_column_double(query, 6)
            let mean = !legacy && seconds > 0 ? sqlite3_column_double(query, 7) / seconds : total / Double(count)
            let peakTime = sqlite3_column_type(query, 8) == SQLITE_NULL ? (count == 1 ? time : nil) : sqlite3_column_double(query, 8)
            let point = TrayHistoryPoint(time: time, value: mean, peak: peak, count: count, session: session,
                                         source: source, seconds: seconds,
                                         peakTime: peakTime, estimated: legacy)
            tiedRows.append(point)
            status = sqlite3_step(query)
        }
        emitBucket()
        try check(status, expected: SQLITE_DONE)
        return points
    }
}
