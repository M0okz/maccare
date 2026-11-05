import Foundation
import MacCareBattery

/// Observe uniquement : ne déclenche aucune commande ni reprise de protection.
struct BatteryAlertDetector {
    private var interruptionSince: TimeInterval?
    private var previous: BatteryAlertObservation?
    private var pendingCycle: (BatteryCycleStatus, TimeInterval)?
    private var pendingTopUp: (Int, TimeInterval)?
    private(set) var interrupted = false
    mutating func reset() { self = Self() }

    mutating func observe(_ observation: BatteryAlertObservation, uptime: TimeInterval,
                          now: Date = Date(), cyclesEnabled: Bool = BatteryCycle.enabledInThisRelease) -> BatteryCompletionAlert? {
        defer { previous = observation }
        guard !observation.terminating else { reset(); return nil }
        if !observation.expected || observation.healthy {
            interruptionSince = nil; interrupted = false
        } else {
            if interruptionSince == nil || uptime < (interruptionSince ?? uptime) { interruptionSince = uptime }
            interrupted = uptime - (interruptionSince ?? uptime) >= 30
        }
        guard let previous, observation.expected, previous.expected, previous.cancellation == observation.cancellation,
              observation.healthy, let status = observation.status, status.ownedByCaller,
              let target = status.configuration?.limit, status.snapshot.reliableForControl else {
            pendingCycle = nil; pendingTopUp = nil
            return nil
        }
        if previous.status?.topUp == true, !status.topUp,
           status.snapshot.onAC, status.snapshot.percent == 100 {
            pendingTopUp = (target, uptime)
        }
        if let pending = pendingTopUp {
            if uptime < pending.1 || uptime - pending.1 > BatteryCycle.powerReturnGrace || target != pending.0 || status.topUp {
                pendingTopUp = nil
            } else if status.snapshot.onAC && observation.limitConfirmed {
                pendingTopUp = nil
                return .init(id: UUID(), operation: .topUp, target: target, createdAt: now)
            }
        }
        guard cyclesEnabled else { pendingCycle = nil; return nil }
        if let cycle = previous.status?.cycle, status.cycle == nil,
           status.message.hasPrefix("Cycle terminé"), cycle.target == target,
           let percent = status.snapshot.percent, percent <= target,
           cycle.phase == .dischargingToLimit || cycle.phase == .returningToLimit ||
               (cycle.phase == .rechargingToFull && target == 100) {
            pendingCycle = (cycle, uptime)
        }
        guard let pending = pendingCycle else { return nil }
        guard uptime >= pending.1, uptime - pending.1 <= BatteryCycle.powerReturnGrace,
              status.cycle == nil, status.configuration?.limit == pending.0.target else {
            pendingCycle = nil; return nil
        }
        guard status.snapshot.onAC, observation.limitConfirmed else { return nil }
        pendingCycle = nil
        return .init(id: UUID(), operation: pending.0.phase == .dischargingToLimit ? .discharge : .calibration,
                     target: target, createdAt: now)
    }
}
