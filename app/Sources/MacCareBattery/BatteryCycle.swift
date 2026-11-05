import Foundation

public struct BatteryCycleStatus: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case dischargingToLimit, chargingToFull, dischargingForCalibration, rechargingToFull, returningToLimit
    }
    public var phase: Phase
    public var target: Int
    public var message: String {
        switch phase {
        case .dischargingToLimit: return "Décharge vers \(target) % · le Mac utilise sa batterie"
        case .chargingToFull: return "Étalonnage 1/4 · recharge complète"
        case .dischargingForCalibration: return "Étalonnage 2/4 · décharge vers 10 %"
        case .rechargingToFull: return "Étalonnage 3/4 · nouvelle recharge complète"
        case .returningToLimit: return "Étalonnage 4/4 · retour à \(target) %"
        }
    }
}

/// Pure bounded state machine. No timers, hardware or wall clock are hidden here.
public struct BatteryCycle: Sendable {
    /// On the M1 validation host external input returned by itself on a 20 V 65 W adapter, and did
    /// not return on a 12 V 30 W supply until the cable was reconnected (5 Nov. 2026). The role of the
    /// supply is not proven. A Mac left without input is reported to the user, who reconnects the cable.
    public static let dischargeAvailable = true
    /// Off: this cycle has never run in full on hardware and would end near 10 % if input does not return.
    public static let calibrationAvailable = false
    // The M1 validation host reports PostDischargeWaitSeconds = 120. Allow the
    // system to reconnect external input before treating its absence as a fault.
    public static let powerReturnGrace: TimeInterval = 180
    // At rest, a healthy battery drains about 5 % per hour: 100 to 10 % takes close to a day.
    public static let chargePhaseLimit: TimeInterval = 12 * 3600
    public static let dischargePhaseLimit: TimeInterval = 36 * 3600
    public static let cycleLimit: TimeInterval = 72 * 3600
    public struct Action: Equatable, Sendable {
        public let discharge: Bool
        public let limit: Int
        public let finished: Bool
    }
    public private(set) var status: BatteryCycleStatus
    private let started: TimeInterval
    private var phaseStarted: TimeInterval
    public init(target: Int, now: TimeInterval) {
        status = .init(phase: .dischargingToLimit, target: target); started = now; phaseStarted = now
    }
    public static func calibration(target: Int, now: TimeInterval) -> Self {
        var cycle = Self(target: target, now: now)
        cycle.status.phase = .chargingToFull
        return cycle
    }
    public mutating func advance(snapshot: BatterySnapshot, now: TimeInterval) throws -> Action {
        guard (50...100).contains(status.target), snapshot.reliableForControl,
              let percent = snapshot.percent, snapshot.reliableTemperature,
              let temperature = snapshot.temperature, temperature < 45,
              now.isFinite, started.isFinite, now >= started, now - started < Self.cycleLimit,
              now - phaseStarted < phaseLimit else {
            throw CycleError()
        }
        switch status.phase {
        case .dischargingToLimit:
            return .init(discharge: percent > status.target, limit: status.target, finished: percent <= status.target)
        case .chargingToFull, .rechargingToFull:
            guard snapshot.onAC || now - phaseStarted <= Self.powerReturnGrace else { throw CycleError() }
            if percent >= 100 && !snapshot.charging {
                status.phase = status.phase == .chargingToFull ? .dischargingForCalibration : .returningToLimit
                phaseStarted = now
            }
        case .dischargingForCalibration:
            if percent <= 10 { status.phase = .rechargingToFull; phaseStarted = now }
        case .returningToLimit:
            break
        }
        if status.phase == .returningToLimit, percent <= status.target {
            return .init(discharge: false, limit: status.target, finished: true)
        }
        let discharge = status.phase == .dischargingForCalibration || status.phase == .returningToLimit
        return .init(discharge: discharge, limit: status.phase == .returningToLimit ? status.target : 100, finished: false)
    }
    private var phaseLimit: TimeInterval {
        switch status.phase {
        case .chargingToFull, .rechargingToFull: return Self.chargePhaseLimit
        case .dischargingToLimit, .dischargingForCalibration, .returningToLimit: return Self.dischargePhaseLimit
        }
    }
    private struct CycleError: LocalizedError {
        var errorDescription: String? { "Cycle interrompu : mesures, température ou durée à vérifier. La restauration de l’alimentation est demandée." }
    }
}
