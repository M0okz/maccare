import Foundation

/// Shared by dashboard and menu bar: no duplicate phone sessions, timer, or background daemon.
actor MobileDeviceBatteryStore {
    static let shared = MobileDeviceBatteryStore()
    typealias Read = @Sendable () async -> MobileDeviceBatteryReader.Result
    private let read: Read
    private var nextAttempt: TimeInterval = 0
    private var lastTime: TimeInterval?
    private var receivedAt: TimeInterval?
    private var cached: [TrayBatteryTelemetry.Accessory] = []
    private var reading = false

    init(read: @escaping Read = { await MobileDeviceBatteryReader.read() }) { self.read = read }

    func accessories(at time: TimeInterval = ProcessInfo.processInfo.systemUptime,
                     lowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled) async -> [TrayBatteryTelemetry.Accessory] {
        if let lastTime, time < lastTime {
            cached.removeAll(); receivedAt = nil; nextAttempt = 0
        }
        lastTime = time
        if let receivedAt, time - receivedAt >= 180 { cached.removeAll() }
        guard !Task.isCancelled, !reading, time >= nextAttempt else { return cached }
        reading = true
        // Reserve before awaiting: a concurrent dashboard/menu-bar call uses the cache.
        nextAttempt = time + 300
        let result = await read()
        reading = false
        // Finish the bounded shared acquisition even if its original view closed meanwhile.
        let now = Date()
        cached = result.accessories.map {
            .init(id: $0.id, name: $0.name, symbol: $0.symbol, percent: $0.percent,
                  receivedAt: now, viaPhone: $0.viaPhone)
        }
        receivedAt = time
        if result.complete && !cached.isEmpty { nextAttempt = time + (lowPower ? 120 : 60) }
        return cached
    }
}
