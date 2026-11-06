import Foundation

/// Cadence des petits chiffres de la carte uniquement ; le détail et les relevés
/// continuent à leur fréquence normale. Les changements de connexion sont immédiats.
struct TrayNetworkReadout {
    private(set) var wifi: TrayMetrics.WiFi?
    private var updatedAt: TimeInterval?

    mutating func record(_ metrics: TrayMetrics) {
        let next = metrics.wifi
        let connectionChanged = wifi?.interface != next?.interface || wifi?.connected != next?.connected || wifi?.powered != next?.powered || wifi?.address != next?.address || wifi?.kind != next?.kind
        let firstRate = wifi?.received == nil && next?.received != nil
        let elapsed = updatedAt.map { metrics.sampledAt - $0 } ?? .infinity
        guard connectionChanged || firstRate || elapsed >= 3 || elapsed < 0 else { return }
        wifi = next
        updatedAt = metrics.sampledAt
    }
}
