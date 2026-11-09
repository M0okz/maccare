import SwiftUI

/// Mesures détaillées et fermeture explicite des processus sélectionnés.
struct TrayMetricDetail: View {
    enum Kind: String, Identifiable { case cpu = "Processeur", gpu = "GPU", memory = "Mémoire", wifi = "Réseau"; var id: String { rawValue } }
    let kind: Kind
    @ObservedObject var metricsStore: TrayMetricsStore
    var height: CGFloat = 680
    private var metrics: TrayMetrics { metricsStore.snapshot.display }
    @StateObject private var processes = TrayProcessController()
    @State private var windowVisible = true
    @State private var historyDuration: TimeInterval = 600
    private var samplesProcesses: Bool { (kind == .cpu || kind == .memory) && windowVisible }

    var body: some View {
        TrayDetailSurface(title: kind.rawValue, height: height) {
            switch kind {
            case .cpu: cpu
            case .gpu: gpu
            case .memory: memory
            case .wifi: TrayWiFiDetail(metricsStore: metricsStore)
            }
            if kind == .cpu || kind == .memory {
                Divider().overlay(.white.opacity(0.1))
                TrayProcessList(controller: processes, memory: kind == .memory)
            }
        }
        .background(WindowVisibilityObserver { windowVisible = $0 })
        .task(id: samplesProcesses) {
            if samplesProcesses { await processes.monitor() }
        }
    }

    @ViewBuilder private var cpu: some View {
        if let cpu = metrics.cpu {
            Text("\(Int(cpu.used * 100)) % utilisés").monospacedDigit().font(.largeTitle)
            historyChart(metricsStore.snapshot.cpu.points)
            row("Utilisateur", value: "\(Int(cpu.user * 100)) %")
            row("Système", value: "\(Int(cpu.system * 100)) %")
            row("Disponible", value: "\(Int(max(0, 1 - cpu.used) * 100)) %")
            row("Température CPU", value: metrics.cpu?.temperature.map { "\(Int($0.rounded())) °C" } ?? "Indisponible")
            row("État thermique", value: thermalTitle)
            row("Temps de fonctionnement", value: "\(Int(ProcessInfo.processInfo.systemUptime / 3600)) h")
            Text("Charge globale de tous les cœurs · valeurs lissées. Historique partagé jusqu’à une heure, relevés regroupés par cinq secondes. Les pics restent conservés.")
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

    private func historyChart(_ points: [TrayHistoryPoint]) -> some View {
        VStack(spacing: 10) {
            TrayHistoryRangePicker(duration: $historyDuration)
            TrayHistoryDetail(points: points, duration: historyDuration)
        }.padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var gpu: some View {
        if let gpu = metrics.gpu {
            Text(gpu.fraction.map { "\(Int(($0 * 100).rounded())) % utilisés" } ?? "Charge indisponible")
                .monospacedDigit().font(.largeTitle)
            historyChart(metricsStore.snapshot.gpu.points)
            row("Carte graphique", value: gpu.model)
            row("Cœurs", value: gpu.cores.map(String.init) ?? "Indisponible")
            row("Température GPU", value: gpu.temperature.map { "\(Int($0.rounded())) °C" } ?? "Indisponible")
        } else { Text("Mesure indisponible") }
    }

    @ViewBuilder private var memory: some View {
        if let memory = metrics.memory {
            TrayMemoryRing(memory: memory)
            historyChart(metricsStore.snapshot.memory.points)
            row("Pression mémoire", value: memory.pressure?.title ?? "Indisponible")
            row("Mémoire utilisée estimée", value: "\(Int(memory.fraction * 100)) %")
            Text("Utilisation estimée : mémoire active non purgeable + résidente système + compressée. La mémoire inactive est considérée comme réutilisable. Ce pourcentage n’est pas la pression mémoire de macOS.")
                .font(.caption).foregroundStyle(.white.opacity(0.75))
        } else { Text("Mesure indisponible") }
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text(value).bold().monospacedDigit()
        }
            .font(.system(size: 12)).accessibilityElement(children: .combine)
    }

    static func speed(_ value: Double?) -> String {
        guard let value else { return "Mesure…" }
        return "\(humanSize(UInt64(max(0, value))))/s"
    }
}
