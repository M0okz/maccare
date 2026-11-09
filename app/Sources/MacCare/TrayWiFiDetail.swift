import SwiftUI

struct WiFiTrafficHistory {
    struct Sample { let time: TimeInterval; let received: Double; let sent: Double }
    private(set) var received = TrayMetricHistory()
    private(set) var sent = TrayMetricHistory()
    var samples: [Sample] {
        zip(received.points, sent.points).map { .init(time: $0.time, received: $0.value, sent: $1.value) }
    }
    private(set) var receivedBytes: Double = 0
    private(set) var sentBytes: Double = 0
    private var interface: String?
    private var previousTime: TimeInterval?

    mutating func pause() { previousTime = nil }

    mutating func record(_ metrics: TrayMetrics) {
        guard let wifi = metrics.wifi else {
            received.record(time: metrics.sampledAt, value: nil)
            sent.record(time: metrics.sampledAt, value: nil)
            pause()
            return
        }
        guard wifi.connected else {
            self = .init()
            return
        }
        let identity = "\(wifi.kind.rawValue):\(wifi.interface):\(wifi.address ?? "")"
        if interface != identity { self = .init(); interface = identity }
        guard let received = wifi.received, let sent = wifi.sent,
              received.isFinite, sent.isFinite, received >= 0, sent >= 0 else {
            self.received.record(time: metrics.sampledAt, value: nil)
            self.sent.record(time: metrics.sampledAt, value: nil)
            pause()
            return
        }
        self.received.record(time: metrics.sampledAt, value: received)
        self.sent.record(time: metrics.sampledAt, value: sent)
        if let previousTime {
            let elapsed = metrics.sampledAt - previousTime
            // Un intervalle après veille ne décrit pas un débit instantané fiable.
            if elapsed > 0 && elapsed <= TrayHistoryPoint.maximumGap {
                receivedBytes += received * elapsed
                sentBytes += sent * elapsed
            }
        }
        previousTime = metrics.sampledAt
    }
}

struct TrayWiFiDetail: View {
    @ObservedObject var metricsStore: TrayMetricsStore
    private var metrics: TrayMetrics { metricsStore.snapshot.display }
    private var traffic: WiFiTrafficHistory { metricsStore.snapshot.traffic }
    @StateObject private var test = InternetSpeedTest()
    @State private var historyDuration: TimeInterval = 600
    private let muted = Color.white.opacity(0.73)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            connection
            TrayHistoryRangePicker(duration: $historyDuration)
            HStack(alignment: .top, spacing: 10) {
                trafficCard(title: "Téléchargement", symbol: "arrow.down", points: traffic.received.points,
                            total: traffic.receivedBytes, current: metrics.wifi?.received, color: .cyan)
                trafficCard(title: "Envoi", symbol: "arrow.up", points: traffic.sent.points,
                            total: traffic.sentBytes, current: metrics.wifi?.sent, color: .pink)
            }
            Text("Trafic de l’interface réseau principale, échanges locaux compris · historique jusqu’à une heure. Débits lissés, moyennes sur cinq secondes et pics conservés. Volumes depuis le début du suivi de cette connexion.")
                .font(.caption2).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            speedTest
        }
        .onChange(of: metrics.sampledAt) { _ in
            if metrics.wifi?.connected != true { test.cancel() }
        }
        .onDisappear { test.cancel() }
    }

    private var connection: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: metrics.network?.symbol ?? "network").font(.title2).foregroundStyle(.cyan).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(connectionTitle).font(.headline)
                if let wifi = metrics.wifi, wifi.connected {
                    Text("\(wifi.interface) · \(wifi.address ?? "IP indisponible")").font(.caption).foregroundStyle(muted)
                        .textSelection(.enabled)
                    if wifi.kind == .wifi && wifi.linkRate > 0 {
                        Text("Liaison Wi-Fi à \(Int(wifi.linkRate)) Mb/s").font(.caption2).foregroundStyle(muted)
                    }
                } else {
                    Text("Connectez le Mac à un réseau pour suivre son trafic.").font(.caption).foregroundStyle(muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var connectionTitle: String {
        guard let network = metrics.network, network.connected else { return "Réseau déconnecté" }
        return "\(network.kind.rawValue) connecté"
    }

    private func trafficCard(title: String, symbol: String, points: [TrayHistoryPoint], total: Double, current: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold))
            Text(NetworkRateFormat.megabits(current)).monospacedDigit()
                .font(.system(size: 20, weight: .semibold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(humanSize(UInt64(total))) transférés").monospacedDigit()
                .font(.system(size: 10)).foregroundStyle(muted)
            TrayHistoryDetail(points: points, duration: historyDuration, color: color,
                              maximum: trafficCeiling(points), network: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func trafficCeiling(_ points: [TrayHistoryPoint]) -> Double {
        let peak = TrayMetricHistory.window(points, duration: historyDuration).map(\.peak).max() ?? 0
        // Paliers partagés ; le détail peut couvrir une période plus longue que la carte.
        var scale = metricsStore.snapshot.networkScale
        scale.record(peak: peak, time: metrics.sampledAt)
        return scale.maximum
    }

    private var speedTest: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Testez votre connexion").font(.headline).accessibilityAddTraits(.isHeader)
            HStack(spacing: 16) {
                Button {
                    if test.running { test.cancel() } else { test.start() }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: test.running ? "stop.fill" : "speedometer").font(.title2)
                        Text(test.running ? "Arrêter" : test.result == nil ? "Tester la vitesse" : "Retester")
                            .font(.system(size: 11, weight: .semibold)).multilineTextAlignment(.center)
                    }
                    .frame(width: 106, height: 106).contentShape(Circle())
                }
                .buttonStyle(SpeedTestButtonStyle())
                .disabled(metrics.wifi?.connected != true)
                .accessibilityLabel(test.running ? "Arrêter le test de vitesse" : "Lancer le test de vitesse Internet")
                VStack(alignment: .leading, spacing: 6) {
                    Text(test.phase).font(.system(size: 13, weight: .semibold))
                    if test.running { ProgressView().controlSize(.small).accessibilityLabel(test.phase) }
                    Text("Téléchargement, envoi et latence HTTP vers Cloudflare.")
                        .font(.caption).foregroundStyle(muted)
                    Text("Connexion Internet active, VPN compris.").font(.caption2).foregroundStyle(muted)
                }
            }
            HStack(spacing: 8) {
                resultCell("Réception", value: mbps(test.downloadMbps))
                resultCell("Envoi", value: mbps(test.uploadMbps))
                resultCell("Latence HTTP", value: test.latencyMilliseconds.map { String(format: "%.0f ms", $0) } ?? "—")
            }
            if let result = test.result {
                Text("Mesuré à \(result.completedAt.formatted(date: .omitted, time: .shortened)) · \(humanSize(UInt64(result.transferredBytes))) transférés")
                    .font(.caption2).foregroundStyle(muted)
            }
            if let error = test.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Au clic uniquement · jusqu’à 72 Mo de données de test. Cloudflare reçoit votre adresse IP. Aucun fichier personnel n’est envoyé.")
                .font(.caption2).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Comprendre la mesure") {
                Text("Test HTTP court à un flux vers speed.cloudflare.com. La durée des échanges est incluse dans le débit : ce résultat peut être inférieur au débit maximal de votre ligne. La latence est un aller-retour HTTP médian, pas un ping ICMP. Les courbes montrent le trafic de l’interface principale, échanges locaux compris ; le test peut emprunter une autre interface selon le routage du Mac.")
                    .font(.caption2).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
        }
    }

    private func mbps(_ value: Double?) -> String { value.map { String(format: "%.1f Mb/s", $0) } ?? "—" }

    private func resultCell(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(muted)
            Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private struct SpeedTestButtonStyle: ButtonStyle {
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.4))
            .background(.white.opacity(configuration.isPressed ? 0.18 : hovered ? 0.12 : 0.07), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(hovered ? 0.30 : 0.12), lineWidth: 2))
            .pressFeedback(configuration.isPressed && enabled)
            .onHover { hovered = $0 }
    }
}
