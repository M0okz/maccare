import Foundation

struct TrayBatteryProcessCadence {
    static let interval: TimeInterval = 15
    static let maximumMeasurementInterval: TimeInterval = 30
    private var lastSample: TimeInterval?
    private var awaitingMeasurement = false

    mutating func shouldSample(at time: TimeInterval) -> Bool {
        let elapsed = lastSample.map { time - $0 }
        let interval: TimeInterval = awaitingMeasurement ? 1 : Self.interval
        if let elapsed, elapsed >= 0, elapsed < interval { return false }
        // Deux relevés rapprochés amorcent les compteurs, aussi après une longue pause.
        awaitingMeasurement = elapsed.map { $0 < 0 || $0 > Self.maximumMeasurementInterval } ?? true
        lastSample = time
        return true
    }
}
