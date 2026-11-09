import Combine
import Foundation

/// Lissage de présentation uniquement : les courbes et volumes gardent les relevés bruts.
struct TrayMetricsSmoothing {
    private var previous: TrayMetrics?

    mutating func apply(_ raw: TrayMetrics) -> TrayMetrics {
        var result = raw
        defer { previous = result }
        guard let previous else { return result }
        let elapsed = raw.sampledAt - previous.sampledAt
        guard elapsed > 0, elapsed <= TrayHistoryPoint.maximumGap else { return result }
        let weight = 1 - exp(-elapsed / 5)
        func blend(_ old: Double, _ new: Double) -> Double { old + (new - old) * weight }
        if let old = previous.cpu, let new = raw.cpu {
            result.cpu = .init(user: blend(old.user, new.user), system: blend(old.system, new.system), temperature: new.temperature)
        }
        if let old = previous.gpu, let new = raw.gpu, old.id == new.id, let oldValue = old.fraction, let value = new.fraction {
            result.gpu = .init(id: new.id, model: new.model, cores: new.cores,
                               fraction: blend(oldValue, value), temperature: new.temperature)
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
    var compact = TrayMetricsReadout()
    var compactNetwork: TrayNetworkReadout { compact.network }
    var memory = TrayMetricHistory()
    var networkScale = TrayNetworkScale()
}

/// Un seul suivi pour l’application, indépendant de la durée de vie du panneau.
@MainActor
final class TrayMetricsStore: ObservableObject {
    enum Consumer: Hashable { case menuBar, dashboard(UUID), activityDetail(UUID) }
    @Published private(set) var snapshot = TrayMetricsSnapshot()
    private var smoothing = TrayMetricsSmoothing()
    private let sampler: any TrayMetricsSampling
    private let sleep: @Sendable (Duration) async throws -> Void
    private var sleeper: Task<Void, Never>?
    private var requested = false
    private var task: Task<Void, Never>?
    private var consumers: Set<Consumer> = []
    private var suspended = false
    private var primingReadings = 0
    var isMonitoring: Bool { task != nil }
    var isForeground: Bool { !consumers.isEmpty }

    init(sampler: any TrayMetricsSampling = TrayMetricsSampler(),
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.sampler = sampler
        self.sleep = sleep
    }

    /// La charge CPU exige deux relevés, et macOS met ses compteurs à jour par à-coups : on
    /// relit vite tant qu’elle manque, pour qu’un volet tout juste ouvert affiche ses valeurs.
    nonisolated static func nextDelay(hasCPU: Bool, reading: Int, foreground: Bool = true) -> Duration {
        !hasCPU && reading < 6 ? .milliseconds(250) : foreground ? .seconds(1) : .seconds(5)
    }

    func setMonitoring(for consumer: Consumer, enabled: Bool) {
        let wasForeground = isForeground
        if enabled { consumers.insert(consumer); requested = true } else { consumers.remove(consumer) }
        reconcileMonitoring()
        // Réveiller la boucle existante sans réinitialiser les compteurs.
        if wasForeground != isForeground { sleeper?.cancel() }
    }
    func suspend() { suspended = true; reconcileMonitoring() }
    func resume() { suspended = false; reconcileMonitoring() }
    private func reconcileMonitoring() {
        if requested && !suspended { startLoop() } else { halt() }
    }

    func start() { requested = true; reconcileMonitoring() }

    private func startLoop() {
        guard task == nil else { return }
        primingReadings = 6
        let sampler = sampler
        let sleep = sleep
        task = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await sampler.reset()
            var reading = 0
            while !Task.isCancelled {
                guard let foreground = self?.isForeground else { return }
                let sample = await sampler.sample(includeSensors: foreground)
                guard !Task.isCancelled else { return }
                self?.record(sample)
                reading += 1
                let delay = Self.nextDelay(hasCPU: sample.cpu != nil, reading: reading, foreground: self?.isForeground == true)
                // Annuler ce délai réveille la boucle lors d’un changement de visibilité.
                let sleeper = Task<Void, Never> { do { try await sleep(delay) } catch {} }
                self?.sleeper = sleeper
                await sleeper.value
                guard !Task.isCancelled else { return }
                self?.sleeper = nil
            }
        }
    }

    func stop() { requested = false; halt() }

    private func halt() {
        task?.cancel()
        task = nil
        sleeper?.cancel()
        sleeper = nil
        smoothing = .init()
        snapshot.traffic.pause()
    }

    func record(_ sample: TrayMetrics) {
        var next = snapshot
        let elapsed = sample.sampledAt - next.raw.sampledAt
        if elapsed < 0 { next = .init() }
        if elapsed > TrayHistoryPoint.maximumGap || elapsed < 0 { smoothing = .init() }
        if let network = sample.wifi,
           network.interface != next.raw.wifi?.interface || network.address != next.raw.wifi?.address || network.kind != next.raw.wifi?.kind {
            next.networkScale = .init()
        }
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
        next.memory.record(time: sample.sampledAt, value: sample.memory?.fraction)
        next.compact.record(next.display)
        let cardTraffic = TrayMetricHistory.window(next.traffic.received.points, duration: TrayMetricHistory.cardDuration)
        next.networkScale.record(peak: cardTraffic.map(\.peak).max() ?? 0, time: sample.sampledAt)
        snapshot = next
    }

    deinit { task?.cancel(); sleeper?.cancel() }
}
