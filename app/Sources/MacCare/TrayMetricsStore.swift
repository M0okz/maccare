import Combine
import Foundation

struct TrayHistoryPoint: Sendable {
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
            result.cpu = .init(user: blend(old.user, new.user), system: blend(old.system, new.system))
        }
        if let old = previous.memory, let new = raw.memory, old.total == new.total {
            result.memory = .init(total: new.total,
                                  active: UInt64(blend(Double(old.active), Double(new.active))),
                                  wired: UInt64(blend(Double(old.wired), Double(new.wired))),
                                  compressed: UInt64(blend(Double(old.compressed), Double(new.compressed))))
        }
        if let old = previous.wifi, let new = raw.wifi, old.interface == new.interface, old.connected, new.connected {
            result.wifi = .init(interface: new.interface, powered: new.powered, connected: new.connected,
                                linkRate: new.linkRate,
                                received: new.received.map { blend(old.received ?? $0, $0) },
                                sent: new.sent.map { blend(old.sent ?? $0, $0) }, signalDBm: new.signalDBm)
        }
        return result
    }
}

struct TrayMetricsSnapshot {
    var raw = TrayMetrics()
    var display = TrayMetrics()
    var cpu = TrayCPUHistory()
    var traffic = WiFiTrafficHistory()
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
    var isMonitoring: Bool { task != nil }
    private nonisolated static let firstIntervalMilliseconds = 250

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
        let sampler = sampler
        task = Task { [weak self] in
            await sampler.reset()
            // La charge CPU et les débits exigent deux relevés : le second arrive vite pour
            // qu’un volet tout juste ouvert affiche ses valeurs sans attendre une seconde.
            var delay = Duration.milliseconds(Self.firstIntervalMilliseconds)
            while !Task.isCancelled {
                let sample = await sampler.sample()
                guard !Task.isCancelled else { return }
                self?.record(sample)
                do { try await Task.sleep(for: delay) } catch { return }
                delay = .seconds(1)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        smoothing = .init()
        snapshot = .init()
    }

    func record(_ sample: TrayMetrics) {
        var next = snapshot
        let elapsed = sample.sampledAt - next.raw.sampledAt
        if elapsed > 3 || elapsed < 0 { next = .init(); smoothing = .init() }
        next.raw = sample
        next.display = smoothing.apply(sample)
        next.cpu.record(sample)
        next.traffic.record(sample)
        snapshot = next
    }

    deinit { task?.cancel() }
}
