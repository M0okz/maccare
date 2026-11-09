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

/// Les nombres des cartes changent toutes les trois secondes. Les capteurs,
/// indisponibilités et changements d’état sont répercutés dès le prochain relevé.
struct TrayMetricsReadout {
    private(set) var metrics = TrayMetrics()
    private(set) var network = TrayNetworkReadout()
    private var updatedAt: TimeInterval?

    mutating func record(_ next: TrayMetrics) {
        network.record(next)
        defer { metrics.wifi = network.wifi }
        let elapsed = updatedAt.map { next.sampledAt - $0 } ?? .infinity
        if elapsed >= 3 || elapsed < 0 {
            metrics = next
            updatedAt = next.sampledAt
            return
        }
        if metrics.cpu == nil || next.cpu == nil { metrics.cpu = next.cpu }
        else { metrics.cpu?.temperature = next.cpu?.temperature }
        if metrics.gpu?.id != next.gpu?.id || metrics.gpu?.fraction == nil || next.gpu?.fraction == nil { metrics.gpu = next.gpu }
        else { metrics.gpu?.temperature = next.gpu?.temperature }
        if metrics.memory?.total != next.memory?.total { metrics.memory = next.memory }
        else { metrics.memory?.pressure = next.memory?.pressure }
        metrics.fans = next.fans
    }
}
