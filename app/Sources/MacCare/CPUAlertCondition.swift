import Foundation

/// Charge globale du Mac ; les pourcentages par processus gardent leur base d’un cœur.
struct CPUAlertCondition {
    /// La charge est lue toutes les 5 s : au-delà de cet écart, la continuité n’est plus établie.
    static let maximumGap: TimeInterval = 15
    private var started: TimeInterval?
    private var last: TimeInterval?
    private(set) var fraction: Double = 0
    private(set) var sustained = false
    mutating func reset() { self = Self() }
    mutating func observe(fraction: Double?, sampledAt: TimeInterval) {
        guard sampledAt.isFinite, let fraction, fraction.isFinite, (0...1).contains(fraction) else { reset(); return }
        if let last, sampledAt <= last || sampledAt - last > Self.maximumGap { reset() }
        self.fraction = fraction; last = sampledAt
        guard fraction >= 0.85 else { started = nil; sustained = false; return }
        if started == nil { started = sampledAt }
        sustained = sampledAt - (started ?? sampledAt) >= 120
    }
    func isFresh(at uptime: TimeInterval) -> Bool {
        guard let last else { return false }
        return uptime >= last && uptime - last <= Self.maximumGap
    }
}
