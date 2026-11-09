import Foundation

struct DeviceLowBatteryPolicy {
    static let thresholdKey = "additionalAlert.deviceBattery.threshold"
    private static let episodesKey = "additionalAlert.deviceBattery.episodes.v1"
    private let defaults: UserDefaults
    private var announced: [String: Date]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.episodesKey), data.count <= 32_768,
           let episodes = try? JSONDecoder().decode([String: Date].self, from: data), episodes.count <= 64 {
            announced = episodes
        } else { announced = [:] }
    }

    var threshold: Int {
        let value = defaults.object(forKey: Self.thresholdKey) as? Int ?? 20
        return (5...50).contains(value) && value % 5 == 0 ? value : 20
    }

    /// Reception time is adequate only for a battery read directly from a trusted device.
    /// An iPhone's cached Watch registry has no verified measurement date; never treat it as live.
    static func isFresh(_ reading: TrayBatteryTelemetry.Accessory, at now: Date) -> Bool {
        guard reading.id.hasPrefix("mobile:"), ["iphone", "ipad"].contains(reading.symbol),
              !reading.viaPhone, (0...100).contains(reading.percent), let received = reading.receivedAt else { return false }
        let age = now.timeIntervalSince(received)
        return age.isFinite && age >= 0 && age <= 180
    }

    mutating func candidates(_ readings: [TrayBatteryTelemetry.Accessory], at now: Date = Date()) -> [TrayBatteryTelemetry.Accessory] {
        guard AdditionalAlertReminder(.deviceBattery, defaults: defaults).enabled else { return [] }
        let fresh = readings.filter { Self.isFresh($0, at: now) }
        var changed = false
        for reading in fresh where reading.percent >= threshold + 5 {
            if announced.removeValue(forKey: reading.id) != nil { changed = true }
        }
        if changed { persist() }
        var seen: Set<String> = []
        return fresh.filter {
            $0.percent <= threshold && announced[$0.id] == nil && seen.insert($0.id).inserted
        }.sorted { $0.percent == $1.percent ? $0.id < $1.id : $0.percent < $1.percent }
    }

    mutating func record(_ reading: TrayBatteryTelemetry.Accessory, at now: Date = Date()) {
        guard AdditionalAlertReminder(.deviceBattery, defaults: defaults).enabled,
              Self.isFresh(reading, at: now), reading.percent <= threshold else { return }
        announced[reading.id] = now
        if announced.count > 64, let oldest = announced.min(by: { $0.value < $1.value })?.key {
            announced.removeValue(forKey: oldest)
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(announced) { defaults.set(data, forKey: Self.episodesKey) }
    }
}
