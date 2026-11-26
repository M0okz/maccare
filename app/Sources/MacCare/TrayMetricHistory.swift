import Foundation

struct TrayHistoryPoint: Sendable {
    static let maximumCount = 721
    static let maximumGap: TimeInterval = 15
    let time: TimeInterval
    let value: Double
    let peak: Double
    let peakTime: TimeInterval?
    let seconds: TimeInterval
    let estimated: Bool

    let count: Int
    let session: Int64
    let source: Int64
    var startsSegment: Bool

    init(time: TimeInterval, value: Double, peak: Double? = nil, count: Int = 1,
         session: Int64 = 0, source: Int64 = 0, startsSegment: Bool = false,
         seconds: TimeInterval = 0, peakTime: TimeInterval? = nil, estimated: Bool = false) {
        self.peakTime = peakTime
        self.seconds = seconds
        self.estimated = estimated
        self.count = count
        self.session = session
        self.source = source
        self.startsSegment = startsSegment
        self.time = time
        self.value = value
        self.peak = peak ?? value
    }

    func merging(_ next: Self) -> Self {
        let duration = seconds + next.seconds
        let n = count + next.count
        let mean = duration > 0
            ? (value * seconds + next.value * next.seconds) / duration
            : (value * Double(count) + next.value * Double(next.count)) / Double(n)
        let date: TimeInterval?
        if peak == next.peak {
            date = Self.earliest(peakTime, next.peakTime)
        } else {
            date = peak > next.peak ? peakTime : next.peakTime
        }
        return .init(time: max(time, next.time), value: mean, peak: max(peak, next.peak), count: n,
                     session: session, source: source, startsSegment: startsSegment, seconds: duration,
                     peakTime: date, estimated: estimated || next.estimated)
    }

    static func earliest(_ a: TimeInterval?, _ b: TimeInterval?) -> TimeInterval? {
        if let a, let b { return min(a, b) }
        return a ?? b
    }
}

/// Tracks coverage of one series. Rates refer to the interval ending at the
/// reading. A first reading (or the first after a gap) gives a peak, but no duration.
struct ActivitySeriesContinuity {
    private var session: Int64?
    private var source: Int64?
    private var segment: Int64 = 0
    private var previousUptime: TimeInterval?

    mutating func pause() { previousUptime = nil }

    mutating func observe(_ value: Double?, time: TimeInterval, uptime: TimeInterval,
                          session: Int64, source: Int64 = 0) -> TrayHistoryPoint? {
        guard let value, value.isFinite, value >= 0, uptime.isFinite, time.isFinite else {
            pause()
            return nil
        }
        let elapsed = previousUptime.map { uptime - $0 }
        let continues = self.session == session && self.source == source
            && elapsed.map { $0 >= 0 && $0 <= TrayHistoryPoint.maximumGap } == true
        if self.session != session { segment = session }
        else if !continues { segment = Int64.random(in: 1...Int64.max) }
        self.session = session
        self.source = source
        previousUptime = uptime
        return .init(time: time, value: value, session: segment, source: source, startsSegment: !continues,
                     seconds: continues ? (elapsed ?? 0) : 0, peakTime: time)
    }
}

/// Une heure bornée en RAM. Chaque point regroupe cinq secondes de vrais relevés,
/// en conservant leur moyenne et leur maximum ; aucun relevé n’est interpolé.
struct TrayMetricHistory {
    static let duration: TimeInterval = 3600
    static let cardDuration: TimeInterval = 600
    static let bucketDuration: TimeInterval = 5
    private(set) var points: [TrayHistoryPoint] = []
    private var bucket: Double?
    private var continuity = ActivitySeriesContinuity()
    init(restoring points: [TrayHistoryPoint] = []) {
        self.points = Array(points.suffix(TrayHistoryPoint.maximumCount))
    }

    mutating func pause() { continuity.pause() }

    @discardableResult
    mutating func record(time: TimeInterval, value: Double?, session: Int64 = 0, uptime: TimeInterval? = nil) -> TimeInterval {
        guard time.isFinite else { return 0 }
        if let last = points.last, time < last.time { self = .init() }
        let cutoff = time - Self.duration - Self.bucketDuration
        if let first = points.first, first.time < cutoff {
            points.removeFirst(points.prefix { $0.time < cutoff }.count)
        }
        guard let point = continuity.observe(value, time: time, uptime: uptime ?? time, session: session) else { return 0 }
        let nextBucket = floor(time / Self.bucketDuration)
        if nextBucket == bucket, !point.startsSegment, let last = points.last {
            points[points.count - 1] = last.merging(point)
        } else {
            bucket = nextBucket
            points.append(point)
        }
        if points.count > TrayHistoryPoint.maximumCount { points.removeFirst(points.count - TrayHistoryPoint.maximumCount) }
        return point.seconds
    }

    static func window(_ points: [TrayHistoryPoint], duration: TimeInterval, end: TimeInterval? = nil) -> [TrayHistoryPoint] {
        guard let end = end ?? points.last?.time else { return [] }
        let start = end - duration
        guard let last = points.lastIndex(where: { $0.time <= end }) else { return [] }
        let first = points[...last].lastIndex { $0.time < start } ?? points.startIndex
        return Array(points[first...last])
    }

    struct Statistics {
        var average: Double?
        var peak: Double?
        var peakTime: TimeInterval?
        var estimated = false
    }

    static func statistics(_ points: [TrayHistoryPoint], duration: TimeInterval, end: TimeInterval? = nil) -> Statistics {
        guard let end = end ?? points.last?.time else { return .init() }
        let start = end - duration
        var result = Statistics()
        var integral = 0.0
        var seconds = 0.0
        for point in points where point.time >= start && point.time <= end {
            let visibleSeconds = min(point.seconds, point.time - start)
            integral += point.value * visibleSeconds
            seconds += visibleSeconds
            result.estimated = result.estimated || point.estimated
            if let date = point.peakTime, date < start { continue }
            if result.peak == point.peak {
                result.peakTime = TrayHistoryPoint.earliest(result.peakTime, point.peakTime)
            } else if result.peak.map({ point.peak > $0 }) ?? true {
                result.peak = point.peak
                result.peakTime = point.peakTime
            }
        }
        if seconds > 0 { result.average = integral / seconds }
        return result
    }
}

extension Array where Element == TrayHistoryPoint {
    func suffix(whileSourceIs source: Int64) -> [Element] {
        let start = lastIndex { $0.source != source }.map { $0 + 1 } ?? startIndex
        return Array(self[start...])
    }
}

struct TrayCPUHistory {
    static let duration = TrayMetricHistory.cardDuration
    private var history = TrayMetricHistory()
    var points: [TrayHistoryPoint] { history.points }
    mutating func restore(_ points: [TrayHistoryPoint]) { history = .init(restoring: points) }

    mutating func record(_ metrics: TrayMetrics, time: TimeInterval? = nil, session: Int64 = 0) {
        history.record(time: time ?? metrics.sampledAt, value: metrics.cpu?.used.mapClampedFraction, session: session, uptime: metrics.sampledAt)
    }
}

private extension Double {
    var mapClampedFraction: Double { isFinite ? min(1, max(0, self)) : self }
}

/// Montée immédiate par paliers ; baisse seulement après une minute à faible trafic.
struct TrayNetworkScale {
    private(set) var maximum: Double = 12_500 // 0,1 Mb/s en octets/s
    private var lowerSince: TimeInterval?

    mutating func record(peak: Double, time: TimeInterval) {
        guard peak.isFinite, peak >= 0, time.isFinite else { return }
        let magnitude = pow(10, floor(log10(max(12_500, peak))))
        let target = max(12_500, ([2.0, 5, 10, 20].first { $0 * magnitude >= peak * 1.15 } ?? 20) * magnitude)
        if target > maximum { maximum = target; lowerSince = nil }
        else if target < maximum / 2 {
            if let lowerSince, time >= lowerSince, time - lowerSince >= 60 { maximum = target; self.lowerSince = nil }
            else if time < (lowerSince ?? .infinity) { lowerSince = time }
        } else { lowerSince = nil }
    }
}
