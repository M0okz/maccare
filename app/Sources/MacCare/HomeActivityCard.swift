import SwiftUI

struct HomeActivityCard: View {
    @ObservedObject var store: TrayMetricsStore
    let storage: TrayStorageUsage?
    let onStorage: () -> Void
    @Environment(\.openWindow) private var openWindow
    @State private var memoryHovered = false
    @State private var cpuHovered = false
    @State private var networkHovered = false
    private var metrics: TrayMetrics { store.snapshot.compact.metrics }
    private var wifi: TrayMetrics.WiFi? { store.snapshot.compactNetwork.wifi ?? metrics.wifi }
    private var networkPoints: [TrayHistoryPoint] {
        store.snapshot.traffic.received.points
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label { Text("Activité du Mac") } icon: {
                Image(systemName: "waveform.path.ecg").foregroundStyle(Theme.accentInk).accessibilityHidden(true)
            }.font(.headline).accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow { cpu; gpu; memory }
                    GridRow { disk; network; fans }
                }.frame(minWidth: 540)
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow { cpu; gpu }
                    GridRow { memory; disk }
                    GridRow { network; fans }
                }
            }.frame(maxHeight: .infinity)
        }
        .modifier(HomeStatusCardStyle(tint: Theme.accent, expandsVertically: true))
    }

    private var cpu: some View {
        Button { openWindow(id: HomeActivityWindow.id(for: .cpu)) } label: {
            HomeActivityTile {
                HStack {
                    metricLabel("Processeur", symbol: "cpu")
                    Spacer(minLength: 4)
                    badge(temperature(metrics.cpu?.temperature), color: Theme.accentInk)
                        .accessibilityLabel("Température du processeur : \(temperature(metrics.cpu?.temperature))")
                }
                Text(metrics.cpu.map { "\(Int(($0.used * 100).rounded())) %" } ?? "—")
                    .font(.title2.weight(.semibold)).monospacedDigit()
                Spacer(minLength: 0)
                TrayHistoryChart(points: store.snapshot.cpu.points, color: Theme.accentInk, filled: true)
                    .frame(height: 24).modifier(HomeActivityGlow(active: cpuHovered, color: Theme.accentInk))
                    .accessibilityHidden(true)
                detail("Charge globale · \(ProcessInfo.processInfo.processorCount) cœurs")
            }
        }
        .buttonStyle(HomeActivityMetricButtonStyle()).onHover { cpuHovered = $0 }
        .help("Charge globale et température maximale des capteurs CPU disponibles. Historique sur 10 minutes, partagé avec le volet.")
        .accessibilityElement(children: .combine).accessibilityHint("Ouvrir l’historique CPU et les processus")
    }

    private var gpu: some View {
        Button { openWindow(id: HomeActivityWindow.id(for: .gpu)) } label: {
            HomeActivityTile {
                HStack {
                    metricLabel("GPU", symbol: "display")
                    Spacer(minLength: 4)
                    badge(temperature(metrics.gpu?.temperature), color: Theme.accentInk)
                        .accessibilityLabel("Température du GPU : \(temperature(metrics.gpu?.temperature))")
                }
                Text(metrics.gpu?.fraction.map { "\(Int(($0 * 100).rounded())) %" } ?? "—")
                    .font(.title2.weight(.semibold)).monospacedDigit()
                Spacer(minLength: 0)
                TrayHistoryChart(points: store.snapshot.gpu.points, color: Theme.accentInk, filled: true)
                    .frame(height: 24).accessibilityHidden(true)
                detail(gpuState)
            }
            .accessibilityElement(children: .combine)
            .help(metrics.gpu?.model ?? "Mesures du GPU indisponibles")
        }
        .buttonStyle(HomeActivityMetricButtonStyle())
        .accessibilityHint("Ouvrir l’historique GPU")
    }

    private var memory: some View {
        Button { openWindow(id: HomeActivityWindow.id(for: .memory)) } label: {
            HomeActivityTile {
                HStack {
                    metricLabel("Mémoire", symbol: "memorychip")
                    Spacer(minLength: 4)
                    badge(metrics.memory?.pressure?.title.replacingOccurrences(of: "Pression ", with: "") ?? "—",
                          color: memoryPressureColor)
                        .accessibilityLabel(metrics.memory?.pressure?.title ?? "Pression mémoire indisponible")
                }
                Text(metrics.memory.map { "\(Int(($0.fraction * 100).rounded())) %" } ?? "—")
                    .font(.title2.weight(.semibold)).monospacedDigit()
                    .accessibilityLabel("Utilisation mémoire estimée : \(metrics.memory.map { "\(Int(($0.fraction * 100).rounded())) %" } ?? "indisponible")")
                Spacer(minLength: 0)
                usageBar(metrics.memory?.fraction, color: ModuleColor.space)
                    .modifier(HomeActivityGlow(active: memoryHovered, color: ModuleColor.space))
                detail(metrics.memory.map { "\(humanSize($0.used)) sur \(humanSize($0.total))" } ?? "Mémoire indisponible")
            }
        }
        .buttonStyle(HomeActivityMetricButtonStyle()).onHover { memoryHovered = $0 }
        .help("Utilisation estimée et pression mesurée par macOS : deux indicateurs distincts.")
        .accessibilityElement(children: .combine).accessibilityHint("Ouvrir la répartition mémoire et les processus")
    }

    private var disk: some View {
        Button(action: onStorage) {
            HomeActivityTile {
                HStack {
                    metricLabel("Stockage", symbol: "internaldrive")
                    Spacer(minLength: 4)
                    badge(storage.map { humanSize($0.total) } ?? "—")
                }
                Text(storage.map { humanSize($0.available) } ?? "—")
                    .font(.title2.weight(.semibold)).monospacedDigit()
                    .accessibilityLabel(storage.map { "Stockage libre : \(humanSize($0.available))" } ?? "Stockage indisponible")
                Spacer(minLength: 0)
                usageBar(storage?.fraction, color: ModuleColor.space)
                detail(storage.map { "\(humanSize($0.used)) utilisés · \($0.percent) %" } ?? "Mesure indisponible")
            }
        }
        .buttonStyle(HomeActivityMetricButtonStyle())
        .help("Stockage interne : espace disponible pour un usage important selon macOS, espace purgeable compris.")
        .accessibilityElement(children: .combine).accessibilityHint("Ouvrir Espace disque")
    }

    private var network: some View {
        Button { openWindow(id: HomeActivityWindow.id(for: .wifi)) } label: {
            HomeActivityTile {
                HStack {
                    metricLabel("Réseau", symbol: wifi?.symbol ?? "network")
                    Spacer(minLength: 4)
                    badge(wifi?.connected == true ? wifi?.kind.rawValue ?? "—" : "Hors ligne")
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("↓ \(NetworkRateFormat.value(wifi?.received))").font(.title2.weight(.semibold))
                    Text("Mb/s").font(AppFont.caption).foregroundStyle(Theme.muted)
                }.monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    .transaction { $0.animation = nil }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Réception : \(NetworkRateFormat.megabits(wifi?.received))")
                detail(wifi?.connected == true ? wifi?.address ?? "IP indisponible" : "Aucune liaison active")
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                TrayHistoryChart(points: wifi?.connected == true ? networkPoints : [], color: ModuleColor.space,
                                 maximum: store.snapshot.networkScale.maximum, filled: true)
                    .frame(height: 24).modifier(HomeActivityGlow(active: networkHovered, color: ModuleColor.space))
                    .accessibilityHidden(true)
                detail("↑ \(NetworkRateFormat.megabits(wifi?.sent))")
                    .accessibilityLabel("Envoi : \(NetworkRateFormat.megabits(wifi?.sent))")
            }
        }
        .buttonStyle(HomeActivityMetricButtonStyle()).onHover { networkHovered = $0 }
        .help("\(wifi?.address ?? "IP indisponible") · \(wifi?.interface ?? "")\nTrafic de l’interface principale, réseau local compris. Ce débit n’est pas un test de vitesse Internet.")
        .accessibilityElement(children: .combine).accessibilityHint("Ouvrir les détails du réseau")
    }

    private var fans: some View {
        HomeActivityTile {
            HStack {
                metricLabel("Ventilateurs", symbol: "fanblades")
                Spacer(minLength: 4)
                badge(metrics.fans?.load.map { "\(Int(($0 * 100).rounded())) %" } ?? "—")
                    .accessibilityLabel(metrics.fans?.load.map { "Vitesse relative maximale : \(Int(($0 * 100).rounded())) %" } ?? "Vitesse relative indisponible")
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(metrics.fans?.fastest.map { "\(Int($0.rounded()))" } ?? "—").font(.title2.weight(.semibold))
                Text("tr/min").font(AppFont.caption).foregroundStyle(Theme.muted)
            }.monospacedDigit()
            Spacer(minLength: 0)
            usageBar(metrics.fans?.load, color: Theme.accentInk)
            detail(metrics.fans?.state ?? "Vitesse indisponible")
        }
        .accessibilityElement(children: .combine)
        .help((metrics.fans?.description ?? "Lecture indisponible") + "\nGestion par macOS, en lecture seule. Le pourcentage est le rapport vitesse mesurée / vitesse maximale.")
    }

    private func metricLabel(_ title: String, symbol: String) -> some View {
        Label { Text(title) } icon: { Image(systemName: symbol).accessibilityHidden(true) }
            .font(AppFont.caption.weight(.medium)).foregroundStyle(Theme.muted).lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
    private func badge(_ title: String, color: Color = Theme.muted) -> some View {
        Text(title).font(AppFont.caption).foregroundStyle(color).monospacedDigit()
            .lineLimit(1).padding(.horizontal, 6).padding(.vertical, 3)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
    }
    private func detail(_ text: String) -> some View {
        Text(text).font(AppFont.caption).foregroundStyle(Theme.muted).lineLimit(1)
    }
    private func usageBar(_ fraction: Double?, color: Color) -> some View {
        GeometryReader { geometry in
            Capsule().fill(.white.opacity(0.08)).overlay(alignment: .leading) {
                Capsule().fill(color).frame(width: geometry.size.width * min(1, max(0, fraction ?? 0)))
            }
        }.frame(height: 6).frame(height: 24).accessibilityHidden(true)
    }
    private func temperature(_ value: Double?) -> String { value.map { "\(Int($0.rounded())) °C" } ?? "— °C" }
    private var gpuState: String {
        guard let gpu = metrics.gpu else { return "Mesures indisponibles" }
        let state = gpu.fraction.map { $0 < 0.01 ? "Au repos" : "Actif" } ?? "Charge indisponible"
        return state + (gpu.cores.map { " · \($0) cœurs" } ?? "")
    }
    private var memoryPressureColor: Color {
        switch metrics.memory?.pressure {
        case .normal: return Theme.ok
        case .warning: return Theme.warn
        case .critical: return Theme.danger
        case nil: return Theme.muted
        }
    }
}
