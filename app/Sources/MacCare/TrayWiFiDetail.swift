import SwiftUI

struct WiFiTrafficHistory {
    struct Sample { let time: TimeInterval; let received: Double; let sent: Double }
    private(set) var samples: [Sample] = []
    private(set) var receivedBytes: Double = 0
    private(set) var sentBytes: Double = 0
    private var interface: String?
    private var previousTime: TimeInterval?

    mutating func record(_ metrics: TrayMetrics) {
        guard let wifi = metrics.wifi, wifi.connected,
              let received = wifi.received, let sent = wifi.sent,
              received.isFinite, sent.isFinite, received >= 0, sent >= 0 else {
            self = .init()
            return
        }
        if interface != wifi.interface { self = .init(); interface = wifi.interface }
        if let previousTime {
            let elapsed = metrics.sampledAt - previousTime
            // Un intervalle après veille ne décrit pas un débit instantané fiable.
            if elapsed > 0 && elapsed <= 10 {
                receivedBytes += received * elapsed
                sentBytes += sent * elapsed
            } else if elapsed > 10 { self = .init(); interface = wifi.interface }
        }
        previousTime = metrics.sampledAt
        samples.append(.init(time: metrics.sampledAt, received: received, sent: sent))
        samples.removeAll { $0.time < metrics.sampledAt - 121 }
    }
}

struct TrayWiFiDetail: View {
    @ObservedObject var metricsStore: TrayMetricsStore
    private var metrics: TrayMetrics { metricsStore.snapshot.display }
    private var traffic: WiFiTrafficHistory { metricsStore.snapshot.traffic }
    @StateObject private var test = InternetSpeedTest()
    private let muted = Color.white.opacity(0.73)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            connection
            HStack(alignment: .top, spacing: 10) {
                trafficCard(title: "Téléchargement", symbol: "arrow.down", points: traffic.samples.map { .init(time: $0.time, value: $0.received) },
                            total: traffic.receivedBytes, current: metrics.wifi?.received, color: .cyan)
                trafficCard(title: "Envoi", symbol: "arrow.up", points: traffic.samples.map { .init(time: $0.time, value: $0.sent) },
                            total: traffic.sentBytes, current: metrics.wifi?.sent, color: .pink)
            }
            Text("Trafic Wi-Fi, échanges locaux compris · 2 dernières minutes. Débits lissés, courbes réelles. Volumes depuis l’activation du suivi.")
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
            Image(systemName: "wifi").font(.title2).foregroundStyle(.cyan).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(connectionTitle).font(.headline)
                if let wifi = metrics.wifi, wifi.connected {
                    Text("\(wifi.interface) · Liaison à \(Int(wifi.linkRate)) Mbit/s").font(.caption).foregroundStyle(muted)
                } else {
                    Text("Connectez le Mac à un réseau Wi-Fi pour suivre son trafic.").font(.caption).foregroundStyle(muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var connectionTitle: String {
        guard let wifi = metrics.wifi else { return "Wi-Fi indisponible" }
        return !wifi.powered ? "Wi-Fi désactivé" : wifi.connected ? "Wi-Fi connecté" : "Wi-Fi non connecté"
    }

    private func trafficCard(title: String, symbol: String, points: [TrayHistoryPoint], total: Double, current: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold))
            Text(TrayMetricDetail.speed(current)).monospacedDigit()
                .font(.system(size: 20, weight: .semibold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(humanSize(UInt64(total))) transférés").monospacedDigit()
                .font(.system(size: 10)).foregroundStyle(muted)
            TrayHistoryChart(points: points, duration: 120, color: color,
                             maximum: trafficCeiling(points.map(\.value).max() ?? 1), filled: true)
                .frame(height: 65).accessibilityLabel("Historique de débit sur deux minutes")
            Text("Pic : \(TrayMetricDetail.speed(points.map(\.value).max()))").font(.system(size: 10)).foregroundStyle(muted)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func trafficCeiling(_ peak: Double) -> Double {
        // Paliers avec de la marge : l’échelle ne change pas pour chaque petit pic.
        let magnitude = pow(10, floor(log10(max(1, peak))))
        return ([2.0, 5, 10, 20].first { $0 * magnitude >= peak * 1.15 } ?? 20) * magnitude
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
                Text("Test HTTP court à un flux vers speed.cloudflare.com. La durée des échanges est incluse dans le débit : ce résultat peut être inférieur au débit maximal de votre ligne. La latence est un aller-retour HTTP médian, pas un ping ICMP. Les courbes Wi-Fi montrent tout le trafic local ; le test peut emprunter une autre interface selon le routage du Mac.")
                    .font(.caption2).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
        }
    }

    private func mbps(_ value: Double?) -> String { value.map { String(format: "%.1f Mbit/s", $0) } ?? "—" }

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
