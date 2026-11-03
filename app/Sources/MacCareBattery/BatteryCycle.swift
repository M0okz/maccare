import Foundation

public struct BatteryCycleStatus: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case dischargingToLimit }
    public var phase: Phase
    public var target: Int
    public var message: String { "Décharge vers \(target) % · le Mac utilise sa batterie" }
}

/// Pure bounded state machine. No timers, hardware or wall clock are hidden here.
public struct BatteryCycle: Sendable {
    public struct Action: Equatable, Sendable {
        public let discharge: Bool
        public let limit: Int
        public let finished: Bool
    }
    public private(set) var status: BatteryCycleStatus
    private let started: TimeInterval
    public init(target: Int, now: TimeInterval) {
        status = .init(phase: .dischargingToLimit, target: target); started = now
    }
    public mutating func advance(snapshot: BatterySnapshot, now: TimeInterval) throws -> Action {
        guard (50...100).contains(status.target), snapshot.reliableForControl,
              let percent = snapshot.percent, snapshot.reliableTemperature,
              let temperature = snapshot.temperature, temperature < 45,
              now.isFinite, started.isFinite, now >= started, now - started < 12 * 3600 else {
            throw CycleError()
        }
        // Once at the target, reconnect input before any normal charge policy resumes.
        return .init(discharge: percent > status.target, limit: status.target, finished: percent <= status.target)
    }
    private struct CycleError: LocalizedError {
        var errorDescription: String? { "Cycle interrompu : mesures, température ou durée à vérifier. L’alimentation est rétablie." }
    }
}
