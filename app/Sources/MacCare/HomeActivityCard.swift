import SwiftUI

struct HomeActivityCard: View {
    @ObservedObject var store: TrayMetricsStore
    @Environment(\.openWindow) private var openWindow
    @State private var memoryHovered = false
    @State private var cpuHovered = false
    @State private var networkHovered = false
    @State private var readout = TrayNetworkReadout()
    private var metrics: TrayMetrics { store.snapshot.display }
    private var wifi: TrayMetrics.WiFi? { readout.wifi ?? metrics.wifi }
    private var networkPoints: [TrayHistoryPoint] {
        store.snapshot.traffic.samples.map { .init(time: $0.time, value: $0.received) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg").foregroundStyle(Theme.accentInk).accessibilityHidden(true)
                Text("Activité du Mac").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
            }
            HStack(alignment: .top, spacing: 12) {
                memory
                Divider().overlay(.white.opacity(0.07))
                cpu
                Divider().overlay(.white.opacity(0.07))
                network
            }.frame(height: 128)
            HStack {
                Text("Utilisation mémoire estimée")
                Spacer(minLength: 4)
                if wifi?.connected == true { Text("↑ \(NetworkRateFormat.megabits(wifi?.sent))").monospacedDigit() }
            }.font(AppFont.caption).foregroundStyle(Theme.muted)
                .transaction { $0.animation = nil }
        }
        .modifier(HomeStatusCardStyle(tint: Theme.accent))
        .onAppear { readout.record(metrics) }
        .onChange(of: metrics.sampledAt) { _ in readout.record(metrics) }
    }

    private var memory: some View {
        Button { openWindow(id: HomeActivityWindow.id(for: .memory)) } label: {
            VStack(alignment: .leading, spacing: 8) {
                metricLabel("RAM", symbol: "memorychip")
                Text(metrics.memory.map { humanSize($0.used) } ?? "—").font(.title2.weight(.semibold)).monospacedDigit()
                Text(metrics.memory.map { "sur \(humanSize($0.total))" } ?? "Lecture en cours…")
                    .font(AppFont.caption).foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                GeometryReader { geometry in
                    Capsule().fill(.white.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Capsule().fill(ModuleColor.space)
                                .frame(width: geometry.size.width * (metrics.memory?.fraction ?? 0))
                                .modifier(HomeActivityGlow(active: memoryHovered, color: ModuleColor.space))
                        }
                }.frame(height: 6).padding(.bottom, 14).accessibilityHidden(true)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(HomeActivityMetricButtonStyle())
            .onHover { memoryHovered = $0 }
            .help("Voir la mémoire active non purgeable, résidente système et compressée.")
            .accessibilityElement(children: .combine)
            .accessibilityHint("Ouvrir la fenêtre RAM")
    }

    private var cpu: some View {
        Button { openWindow(id: HomeActivityWindow.id(for: .cpu)) } label: {
            VStack(alignment: .leading, spacing: 8) {
                metricLabel("CPU", symbol: "cpu")
                Text(metrics.cpu.map { "\(Int(($0.used * 100).rounded())) %" } ?? "—")
                    .font(.title2.weight(.semibold)).monospacedDigit()
                Text(metrics.cpu == nil ? "Mesure en cours…" : "d’utilisation")
                    .font(AppFont.caption).foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                TrayHistoryChart(points: store.snapshot.cpu.points, color: Theme.accentInk, filled: true)
                    .frame(height: 36)
                    .modifier(HomeActivityGlow(active: cpuHovered, color: Theme.accentInk))
                    .accessibilityHidden(true)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(HomeActivityMetricButtonStyle())
            .onHover { cpuHovered = $0 }
            .help("Charge globale de tous les cœurs. Historique réel sur 40 secondes.")
            .accessibilityElement(children: .combine)
            .accessibilityHint("Ouvrir la fenêtre CPU")
    }

    private var network: some View {
        Button { openWindow(id: HomeActivityWindow.id(for: .wifi)) } label: {
            VStack(alignment: .leading, spacing: 8) {
                metricLabel("Réseau", symbol: wifi?.symbol ?? "network")
                Text(download).font(AppFont.emphasis).monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
                    .transaction { $0.animation = nil }
                Text(connection).font(AppFont.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if wifi?.connected == true {
                    TrayHistoryChart(points: networkPoints, color: ModuleColor.space,
                                     maximum: max(1, networkPoints.map(\.value).max() ?? 1), filled: true)
                        .frame(height: 30)
                        .modifier(HomeActivityGlow(active: networkHovered, color: ModuleColor.space))
                        .accessibilityHidden(true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(HomeActivityMetricButtonStyle())
            .onHover { networkHovered = $0 }
            .help("Trafic de l’interface réseau principale, échanges locaux compris. Ce débit n’est pas un test de vitesse Internet.")
            .accessibilityElement(children: .combine)
            .accessibilityHint("Ouvrir la fenêtre Réseau")
    }
    private func metricLabel(_ title: String, symbol: String) -> some View {
        Label { Text(title) } icon: { Image(systemName: symbol).accessibilityHidden(true) }
            .font(AppFont.caption).foregroundStyle(Theme.muted)
    }
    private var download: String {
        guard let wifi else { return "—" }
        return wifi.connected ? NetworkRateFormat.megabits(wifi.received) : "—"
    }
    private var connection: String {
        guard let wifi, wifi.connected else { return "Réseau déconnecté" }
        return "↓ réception · \(wifi.kind.rawValue)"
    }
}
