import Foundation

/// Les sources d’accessoires macOS peuvent manquer pendant plusieurs relevés.
/// Un niveau récent reste affichable, puis expire sans être assimilé à zéro.
struct TrayBatteryAccessoryHistory {
    static let lifetime: TimeInterval = 20
    private struct Entry {
        var accessory: TrayBatteryTelemetry.Accessory
        var sourceID: String
        var lastSeen: TimeInterval
    }
    private var entries: [Entry] = []
    private var previousTime: TimeInterval?
    private var sequence = 0

    mutating func record(_ accessories: [TrayBatteryTelemetry.Accessory], at time: TimeInterval) -> [TrayBatteryTelemetry.Accessory] {
        if let previousTime, time < previousTime { entries.removeAll() }
        previousTime = time
        entries.removeAll { time - $0.lastSeen >= Self.lifetime }
        var updated: Set<Int> = []
        for accessory in accessories {
            // Le numéro de source IOPS peut changer entre deux listes ou lors du repli HID.
            let candidates = entries.indices.filter {
                !updated.contains($0) && entries[$0].accessory.name == accessory.name && entries[$0].accessory.symbol == accessory.symbol &&
                    (entries[$0].sourceID.hasPrefix("mobile:") == accessory.id.hasPrefix("mobile:"))
            }
            let sameSource = candidates.first { entries[$0].sourceID == accessory.id }
            let uniqueName = accessories.filter { $0.name == accessory.name && $0.symbol == accessory.symbol }.count == 1
            let match = sameSource ?? (!accessory.id.hasPrefix("mobile:") && uniqueName && candidates.count == 1 ? candidates.first : nil)
            if let match {
                let stableID = entries[match].accessory.id
                entries[match] = .init(accessory: .init(id: stableID, name: accessory.name, symbol: accessory.symbol, percent: accessory.percent),
                                       sourceID: accessory.id, lastSeen: time)
                entries[match].accessory.receivedAt = accessory.receivedAt
                entries[match].accessory.viaPhone = accessory.viaPhone
                updated.insert(match)
            } else {
                sequence += 1
                let stable = TrayBatteryTelemetry.Accessory(id: "accessory:\(sequence)", name: accessory.name,
                                                            symbol: accessory.symbol, percent: accessory.percent,
                                                            receivedAt: accessory.receivedAt, viaPhone: accessory.viaPhone)
                entries.append(.init(accessory: stable, sourceID: accessory.id, lastSeen: time))
                updated.insert(entries.count - 1)
            }
        }
        return entries.map(\.accessory)
    }
}
