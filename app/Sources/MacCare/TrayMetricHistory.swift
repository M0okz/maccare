import Foundation

struct TrayHistoryPoint: Sendable {
    static let maximumCount = 721
    static let maximumGap: TimeInterval = 15
    let time: TimeInterval
    let value: Double
    let peak: Double

    init(time: TimeInterval, value: Double, peak: Double? = nil) {
        self.time = time
        self.value = value
        self.peak = peak ?? value
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
    private var count = 0

    mutating func record(time: TimeInterval, value: Double?) {
        guard time.isFinite else { return }
        if let last = points.last, time < last.time { self = .init() }
        points.removeAll { $0.time < time - Self.duration - Self.bucketDuration }
        guard let value, value.isFinite, value >= 0 else { return }
        let nextBucket = floor(time / Self.bucketDuration)
        if bucket == nextBucket, let last = points.last {
            count += 1
            points[points.count - 1] = .init(time: time, value: last.value + (value - last.value) / Double(count),
                                            peak: max(last.peak, value))
        } else {
            count = 1
            bucket = nextBucket
            points.append(.init(time: time, value: value))
        }
        if points.count > TrayHistoryPoint.maximumCount { points.removeFirst(points.count - TrayHistoryPoint.maximumCount) }
    }

    static func window(_ points: [TrayHistoryPoint], duration: TimeInterval, end: TimeInterval? = nil) -> [TrayHistoryPoint] {
        guard let end = end ?? points.last?.time else { return [] }
        let start = end - duration
        let first = points.firstIndex { $0.time >= start } ?? points.endIndex
        return Array(points[max(0, first - 1)...])
    }

    static func statistics(_ points: [TrayHistoryPoint], duration: TimeInterval) -> (average: Double?, peak: Double?) {
        guard let end = points.last?.time else { return (nil, nil) }
        let visible = points.filter { $0.time >= end - duration }
        guard !visible.isEmpty else { return (nil, nil) }
        return (visible.reduce(0) { $0 + $1.value } / Double(visible.count), visible.map(\.peak).max())
    }
}

struct TrayCPUHistory {
    static let duration = TrayMetricHistory.cardDuration
    private var history = TrayMetricHistory()
    var points: [TrayHistoryPoint] { history.points }
    mutating func record(_ metrics: TrayMetrics) {
        history.record(time: metrics.sampledAt, value: metrics.cpu?.used.mapClampedFraction)
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
