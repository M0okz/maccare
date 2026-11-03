import SwiftUI

/// Mesures détaillées et fermeture explicite des processus sélectionnés.
struct TrayMetricDetail: View {
    enum Kind: String, Identifiable { case cpu = "Processeur", memory = "Mémoire", wifi = "Wi-Fi"; var id: String { rawValue } }
    let kind: Kind
    @ObservedObject var metricsStore: TrayMetricsStore
    var height: CGFloat = 680
    private var metrics: TrayMetrics { metricsStore.snapshot.display }
    @StateObject private var processes = TrayProcessController()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(kind == .wifi ? "Réseau" : kind.rawValue).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                switch kind {
                case .cpu: cpu
                case .memory: memory
                case .wifi: TrayWiFiDetail(metricsStore: metricsStore)
                }
                if kind != .wifi {
                    Divider().overlay(.white.opacity(0.1))
                    TrayProcessList(controller: processes, memory: kind == .memory)
                }
            }
            .padding(20)
        }
        .frame(width: 390, height: height)
        .task(id: kind) {
            if kind != .wifi { await processes.monitor() }
        }
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [Color(red: 0.24, green: 0.10, blue: 0.45), Color(red: 0.08, green: 0.03, blue: 0.20)], startPoint: .topTrailing, endPoint: .bottomLeading))
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var cpu: some View {
        if let cpu = metrics.cpu {
            TrayRollingValue(text: "\(Int(cpu.used * 100)) % utilisés", value: cpu.used * 100).font(.largeTitle)
            chart
            row("Utilisateur", value: "\(Int(cpu.user * 100)) %", number: cpu.user * 100)
            row("Système", value: "\(Int(cpu.system * 100)) %", number: cpu.system * 100)
            row("Disponible", value: "\(Int(max(0, 1 - cpu.used) * 100)) %", number: max(0, 1 - cpu.used) * 100)
            row("État thermique", value: thermalTitle)
            row("Temps de fonctionnement", value: "\(Int(ProcessInfo.processInfo.systemUptime / 3600)) h")
            Text("Charge globale de tous les cœurs · valeurs lissées. Historique réel des 40 dernières secondes, conservé tant que le suivi MacCare est actif.")
                .font(.caption).foregroundStyle(.white.opacity(0.75))
        } else { Text("Mesure en cours…") }
    }

    private var thermalTitle: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Normal"
        case .fair: return "Modéré"
        case .serious: return "Élevé"
        case .critical: return "Critique"
        @unknown default: return "Indisponible"
        }
    }

    private var chart: some View {
        VStack(spacing: 8) {
            ZStack {
                VStack {
                    ForEach(0..<3) { index in
                        Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                        if index < 2 { Spacer() }
                    }
                }
                TrayHistoryChart(points: metricsStore.snapshot.cpu.points, filled: true)
            }.frame(height: 100)
            HStack {
                Text("−40 s")
                Spacer()
                Text("−20 s")
                Spacer()
                Text("Maintenant")
            }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.65))
            if metricsStore.snapshot.cpu.points.count < 3 {
                Text("Collecte de l’historique…").font(.caption2).foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Historique de la charge CPU, 40 dernières secondes")
        .accessibilityValue("\(metricsStore.snapshot.cpu.points.count) relevés, de 0 à 100 pour cent")
    }

    @ViewBuilder private var memory: some View {
        if let memory = metrics.memory {
            TrayMemoryRing(memory: memory)
            row("Mémoire utilisée estimée", value: "\(Int(memory.fraction * 100)) %", number: memory.fraction * 100)
            Text("Utilisation estimée : mémoire active non purgeable + résidente système + compressée. La mémoire inactive est considérée comme réutilisable. Ce pourcentage n’est pas la pression mémoire de macOS.")
                .font(.caption).foregroundStyle(.white.opacity(0.75))
        } else { Text("Mesure indisponible") }
    }

    private func row(_ title: String, value: String, number: Double? = nil) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.8))
            Spacer()
            if let number { TrayRollingValue(text: value, value: number).bold() }
            else { Text(value).bold().monospacedDigit() }
        }
            .font(.system(size: 12)).accessibilityElement(children: .combine)
    }

    static func speed(_ value: Double?) -> String {
        guard let value else { return "Mesure…" }
        return "\(humanSize(UInt64(max(0, value))))/s"
    }
}
