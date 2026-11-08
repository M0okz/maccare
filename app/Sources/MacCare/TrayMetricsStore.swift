import Combine
import Foundation

struct TrayHistoryPoint: Sendable {
    static let maximumCount = 180
    static let maximumGap: TimeInterval = 3
    let time: TimeInterval
    let value: Double
}

struct TrayCPUHistory {
    static let duration: TimeInterval = 40
    private(set) var points: [TrayHistoryPoint] = []

    mutating func record(_ metrics: TrayMetrics) {
        // Un seul point antérieur au bord gauche sert à tracer le segment coupé.
        let cutoff = metrics.sampledAt - Self.duration - 1
        points.removeAll { $0.time < cutoff }
        guard let value = metrics.cpu?.used, value.isFinite else { return }
        points.append(.init(time: metrics.sampledAt, value: min(1, max(0, value))))
        if points.count > TrayHistoryPoint.maximumCount { points.removeFirst(points.count - TrayHistoryPoint.maximumCount) }
    }
}

/// Lissage de présentation uniquement : les courbes et volumes gardent les relevés bruts.
struct TrayMetricsSmoothing {
    private var previous: TrayMetrics?

    mutating func apply(_ raw: TrayMetrics) -> TrayMetrics {
        var result = raw
        defer { previous = result }
        guard let previous else { return result }
        let elapsed = raw.sampledAt - previous.sampledAt
        guard elapsed > 0, elapsed <= 3 else { return result }
        let weight = 1 - exp(-elapsed / 1.5)
        func blend(_ old: Double, _ new: Double) -> Double { old + (new - old) * weight }
        if let old = previous.cpu, let new = raw.cpu {
            result.cpu = .init(user: blend(old.user, new.user), system: blend(old.system, new.system), temperature: new.temperature)
        }
        if let old = previous.memory, let new = raw.memory, old.total == new.total {
            result.memory = .init(total: new.total,
                                  active: UInt64(blend(Double(old.active), Double(new.active))),
                                  wired: UInt64(blend(Double(old.wired), Double(new.wired))),
                                  compressed: UInt64(blend(Double(old.compressed), Double(new.compressed))), pressure: new.pressure)
        }
        if let old = previous.wifi, let new = raw.wifi, old.interface == new.interface, old.address == new.address, old.kind == new.kind, old.connected, new.connected {
            result.wifi = .init(interface: new.interface, powered: new.powered, connected: new.connected,
                                linkRate: new.linkRate,
                                received: new.received.map { blend(old.received ?? $0, $0) },
                                sent: new.sent.map { blend(old.sent ?? $0, $0) }, signalDBm: new.signalDBm, kind: new.kind, address: new.address)
        }
        return result
    }
}

struct TrayMetricsSnapshot {
    var raw = TrayMetrics()
    var display = TrayMetrics()
    var cpu = TrayCPUHistory()
    var traffic = WiFiTrafficHistory()
    var gpu = TrayGPUHistory()
    var compactNetwork = TrayNetworkReadout()
}

/// Un seul suivi pour l’application, indépendant de la durée de vie du panneau.
@MainActor
final class TrayMetricsStore: ObservableObject {
    enum Consumer: Hashable { case menuBar, dashboard(UUID), activityDetail(UUID) }
    @Published private(set) var snapshot = TrayMetricsSnapshot()
    private var smoothing = TrayMetricsSmoothing()
    private let sampler = TrayMetricsSampler()
    private var task: Task<Void, Never>?
    private var consumers: Set<Consumer> = []
    private var suspended = false
    private var primingReadings = 0
    var isMonitoring: Bool { task != nil }

    /// La charge CPU exige deux relevés, et macOS met ses compteurs à jour par à-coups : on
    /// relit vite tant qu’elle manque, pour qu’un volet tout juste ouvert affiche ses valeurs.
    nonisolated static func nextDelay(hasCPU: Bool, reading: Int) -> Duration {
        !hasCPU && reading < 6 ? .milliseconds(250) : .seconds(1)
    }

    func setMonitoring(for consumer: Consumer, enabled: Bool) {
        if enabled { consumers.insert(consumer) } else { consumers.remove(consumer) }
        reconcileMonitoring()
    }
    func suspend() { suspended = true; stop() }
    func resume() { suspended = false; reconcileMonitoring() }
    private func reconcileMonitoring() {
        if !suspended && !consumers.isEmpty { start() } else { stop() }
    }

    func start() {
        guard task == nil else { return }
        primingReadings = 6
        let sampler = sampler
        task = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await sampler.reset()
            var reading = 0
            while !Task.isCancelled {
                let sample = await sampler.sample()
                guard !Task.isCancelled else { return }
                self?.record(sample)
                reading += 1
                do { try await Task.sleep(for: Self.nextDelay(hasCPU: sample.cpu != nil, reading: reading)) } catch { return }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        smoothing = .init()
        // Le cache appartient à l’application ; seul le suivi dépend de la visibilité.
        snapshot.traffic.pause()
    }

    func record(_ sample: TrayMetrics) {
        var next = snapshot
        let elapsed = sample.sampledAt - next.raw.sampledAt
        if elapsed < 0 { next = .init() }
        if elapsed > TrayHistoryPoint.maximumGap || elapsed < 0 { smoothing = .init() }
        next.raw = sample
        next.display = smoothing.apply(sample)
        // Les compteurs repartent d’une base fraîche. Garder brièvement les chiffres
        // affichés, sans ajouter de faux points ni intégrer le trafic de la pause.
        if primingReadings > 0 {
            primingReadings -= 1
            if sample.cpu == nil { next.display.cpu = snapshot.display.cpu }
            if let current = next.display.wifi, let cached = snapshot.display.wifi,
               current.connected, cached.connected, current.interface == cached.interface,
               current.address == cached.address, current.kind == cached.kind {
                next.display.wifi = .init(interface: current.interface, powered: current.powered, connected: current.connected,
                                linkRate: current.linkRate, received: current.received ?? cached.received,
                                sent: current.sent ?? cached.sent, signalDBm: current.signalDBm,
                                kind: current.kind, address: current.address)
            }
        }
        next.cpu.record(sample)
        next.gpu.record(sample)
        next.traffic.record(sample)
        next.compactNetwork.record(next.display)
        snapshot = next
    }

    deinit { task?.cancel() }
}
