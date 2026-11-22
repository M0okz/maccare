import Foundation

/// The dashboard remembers its last three rings. Other surfaces only use recent readings.
@MainActor
final class TrayBatteryAccessoryHistory {
    typealias Accessory = TrayBatteryTelemetry.Accessory
    nonisolated static let lifetime: TimeInterval = 20
    static let dashboard = TrayBatteryAccessoryHistory(defaults: .standard)
    private static let defaultsKey = AppBuildIdentity.isDevelopment ? "battery.homeRings.dev.v1" : "battery.homeRings.v1"

    private struct Entry {
        let id: String
        var reading: Accessory
        var lastSeen: TimeInterval?

        func isRecent(at time: TimeInterval) -> Bool {
            guard let lastSeen else { return false }
            return time >= lastSeen && time - lastSeen < TrayBatteryAccessoryHistory.lifetime
        }

        func display(at time: TimeInterval) -> Accessory {
            var result = reading
            result.id = id
            result.isLastKnown = !isRecent(at: time)
            return result
        }
    }

    private let defaults: UserDefaults?
    private var entries: [Entry] = []
    private var saved: [Accessory] = []
    private var previousTime: TimeInterval?
    private var sequence = 0
    private(set) var rings: [Accessory] = []

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        guard let data = defaults?.data(forKey: Self.defaultsKey),
              let readings = try? JSONDecoder().decode([Accessory].self, from: data) else { return }
        var ids = Set<String>()
        for reading in readings.prefix(3) where (0...100).contains(reading.percent) && ids.insert(reading.id).inserted {
            append(reading, at: nil)
        }
        saved = entries.map(\.reading)
        rings = entries.map { $0.display(at: 0) }
    }

    private func append(_ reading: Accessory, at time: TimeInterval?) {
        sequence += 1
        entries.append(.init(id: "accessory:\(sequence)", reading: reading, lastSeen: time))
    }

    func record(_ accessories: [Accessory], at time: TimeInterval) -> [Accessory] {
        if let previousTime, time < previousTime {
            for index in entries.indices { entries[index].lastSeen = nil }
        }
        previousTime = time
        let retained = Set(rings.map(\.id))
        entries.removeAll { !retained.contains($0.id) && !$0.isRecent(at: time) }

        var updated = Set<Int>()
        let incomingIDs = Set(accessories.map(\.id))
        for reading in accessories where (0...100).contains(reading.percent) {
            // IOPS/HID identifiers can change. Only fall back to an unambiguous native name and type.
            let mobile = reading.id.hasPrefix("mobile:")
            let candidates = entries.indices.filter {
                let old = entries[$0].reading
                return !updated.contains($0) && old.id.hasPrefix("mobile:") == mobile &&
                    ((mobile && old.id == reading.id) || (old.name == reading.name && old.symbol == reading.symbol))
            }
            let sameID = candidates.first { entries[$0].reading.id == reading.id }
            let uniqueName = accessories.filter { $0.name == reading.name && $0.symbol == reading.symbol }.count == 1
            let fallback = candidates.count == 1 && uniqueName && !mobile ? candidates.first : nil
            if let index = sameID ?? fallback.flatMap({ incomingIDs.contains(entries[$0].reading.id) ? nil : $0 }) {
                entries[index].reading = reading
                entries[index].lastSeen = time
                updated.insert(index)
            } else {
                append(reading, at: time)
                updated.insert(entries.count - 1)
            }
        }

        let recent = entries.filter { $0.isRecent(at: time) }.map { $0.display(at: time) }
        if let defaults { updateRings(recent: recent, at: time, defaults: defaults) }
        return recent
    }

    private func updateRings(recent: [Accessory], at time: TimeInterval, defaults: UserDefaults) {
        let active = Array(TrayBatteryTelemetry(accessories: recent).featuredAccessories.prefix(3))
        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let missing = rings.compactMap { entriesByID[$0.id] }.filter { !$0.isRecent(at: time) }
        let retained = Set(missing.sorted { ($0.lastSeen ?? -.infinity) > ($1.lastSeen ?? -.infinity) }
            .prefix(3 - active.count).map(\.id))

        // Leave missing rings in their slots while there is room for every selected live device.
        var live = active.makeIterator()
        let previous = rings
        rings = previous.compactMap { old in
            retained.contains(old.id) ? entriesByID[old.id]?.display(at: time) : live.next()
        }
        rings.append(contentsOf: live)

        let readings = rings.compactMap { entriesByID[$0.id]?.reading }
        if readings != saved, let data = try? JSONEncoder().encode(readings) {
            defaults.set(data, forKey: Self.defaultsKey)
            saved = readings
        }
    }
}
