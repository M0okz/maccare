import Foundation

public enum FanControlError: LocalizedError {
    case unsupported, occupied, thermal, rejected, restore

    public var errorDescription: String? {
        switch self {
        case .unsupported: return "Ce Mac ne propose pas de commande de vitesse compatible."
        case .occupied: return "Un autre réglage contrôle déjà les ventilateurs."
        case .thermal: return "La température demande de laisser la gestion à macOS."
        case .rejected: return "Le matériel n’a pas confirmé le réglage demandé."
        case .restore: return "Le retour en mode automatique reste à confirmer."
        }
    }
}

public protocol FanBoostHardware {
    func automaticModes() throws -> [Bool]
    func thermalsAllowBoost() -> Bool
    func fansResponding(mask: UInt8) -> Bool
    func boost(fan: Int, maximum: Bool, replacingBoost: Bool) -> (success: Bool, attempted: Bool)
    func restore(fan: Int) -> Bool
    func record(mask: UInt8) throws
}

/// Accessed serially by the helper. A set bit covers a single fan whose mode we may have changed.
public final class FanBoostSession {
    public private(set) var mask: UInt8
    private let hardware: any FanBoostHardware
    private var deadline: Date?
    private var lastCheck: Date?
    private var checkSpeedAfter = Date.distantFuture

    public init(hardware: any FanBoostHardware, recoveryMask: UInt8) {
        self.hardware = hardware
        mask = recoveryMask
    }

    public func apply(_ preset: FanPreset, now: Date) throws {
        let previouslyControlled = deadline == nil ? 0 : mask
        try restore()
        guard preset != .automatic else { return }
        let modes = try hardware.automaticModes()
        guard (1...8).contains(modes.count) else { throw FanControlError.unsupported }
        guard modes.allSatisfy({ $0 }) else { throw FanControlError.occupied }
        guard hardware.thermalsAllowBoost() else { throw FanControlError.thermal }
        do {
            for index in modes.indices {
                let bit = UInt8(1) << index
                try record(mask | bit)
                let result = hardware.boost(fan: index, maximum: preset == .maximum,
                                            replacingBoost: previouslyControlled & bit != 0)
                if !result.attempted { try record(mask & ~bit) }
                guard result.success else { throw FanControlError.rejected }
            }
        } catch {
            try restore()
            throw error
        }
        checkSpeedAfter = now.addingTimeInterval(15)
        deadline = now.addingTimeInterval(300)
        lastCheck = now
    }

    public func check(now: Date) throws {
        guard mask != 0 else { return }
        let gap = lastCheck.map { now.timeIntervalSince($0) } ?? .infinity
        guard let deadline, now < deadline, (0...8).contains(gap), hardware.thermalsAllowBoost(),
              now < checkSpeedAfter || hardware.fansResponding(mask: mask) else {
            try restore()
            return
        }
        lastCheck = now
    }

    private func restore() throws {
        deadline = nil
        lastCheck = nil
        for index in 0..<8 {
            let bit = UInt8(1) << index
            if mask & bit != 0, hardware.restore(fan: index) {
                try record(mask & ~bit)
            }
        }
        if mask != 0 { throw FanControlError.restore }
    }

    private func record(_ value: UInt8) throws {
        try hardware.record(mask: value)
        mask = value
    }
}
