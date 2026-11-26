import SwiftUI

struct HomeActivityCard<Health: View, Battery: View>: View {
    @ObservedObject var store: HomeMetricsStore
    let storage: TrayStorageUsage?
    let availableWidth: CGFloat
    let onStorage: () -> Void
    @ViewBuilder let health: () -> Health
    @ViewBuilder let battery: () -> Battery
    @State private var memoryHovered = false
    @State private var cpuHovered = false
    @State private var gpuHovered = false
    @State private var diskHovered = false
    @State private var networkHovered = false
    private var metrics: TrayMetrics { store.snapshot.compact.metrics }
    private var wifi: TrayMetrics.WiFi? { store.snapshot.compactNetwork.wifi ?? metrics.wifi }
    private var networkPoints: [TrayHistoryPoint] {
        store.snapshot.traffic.received.points
    }

    private var wide: Bool { availableWidth >= 810 }

    var body: some View {
        HomeCardGrid(width: availableWidth, wide: wide) {
            health()
            if wide {
                cpu
                gpu
                memory
                battery()
                disk
            } else {
                battery()
                cpu
                gpu
                memory
                disk
            }
            network
            fans
        }
    }

    private var cpu: some View {
        HomeActivityTile {
            metricHeader("CPU", symbol: "cpu") {
                badge(temperature(metrics.cpu?.temperature), color: Theme.accentInk)
                    .accessibilityLabel("Température du processeur : \(temperature(metrics.cpu?.temperature))")
            }
        } value: {
            reading(metrics.cpu.map { "\(Int(($0.used * 100).rounded()))" }, unit: "%")
        } footer: {
            TrayHistoryChart(points: store.snapshot.cpu.points, color: Theme.accentInk, filled: true, endTime: store.snapshot.historyTime)
                .frame(height: 24).modifier(HomeActivityGlow(active: cpuHovered, color: Theme.accentInk))
                .accessibilityHidden(true)
            detail("\(ProcessInfo.processInfo.processorCount) cœurs")
        }
        .onHover { cpuHovered = $0 }
        .help("Charge globale et température maximale des capteurs CPU disponibles. Historique sur 10 minutes, partagé avec le volet.")
        .accessibilityElement(children: .combine)
    }

    private var gpu: some View {
        HomeActivityTile {
            metricHeader("GPU", symbol: "display") {
                badge(temperature(metrics.gpu?.temperature), color: Theme.accentInk)
                    .accessibilityLabel("Température du GPU : \(temperature(metrics.gpu?.temperature))")
            }
        } value: {
            reading(metrics.gpu?.fraction.map { "\(Int(($0 * 100).rounded()))" }, unit: "%")
        } footer: {
            TrayHistoryChart(points: store.snapshot.gpu.points, color: ModuleColor.startup, filled: true, endTime: store.snapshot.historyTime)
                .frame(height: 24).modifier(HomeActivityGlow(active: gpuHovered, color: ModuleColor.startup))
                .accessibilityHidden(true)
            detail(gpuState)
        }
        .onHover { gpuHovered = $0 }
        .accessibilityElement(children: .combine)
        .help(metrics.gpu?.model ?? "Mesures du GPU indisponibles")
    }

    private var memory: some View {
        HomeActivityTile {
            metricHeader("Mémoire", symbol: "memorychip") {
                badge(metrics.memory?.pressure?.title.replacingOccurrences(of: "Pression ", with: "") ?? "—",
                      color: memoryPressureColor)
                    .accessibilityLabel(metrics.memory?.pressure?.title ?? "Pression mémoire indisponible")
            }
        } value: {
            reading(metrics.memory.map { "\(Int(($0.fraction * 100).rounded()))" }, unit: "%")
                .accessibilityLabel("Utilisation mémoire estimée : \(metrics.memory.map { "\(Int(($0.fraction * 100).rounded())) %" } ?? "indisponible")")
        } footer: {
            TrayHistoryChart(points: store.snapshot.memory.points, duration: 60, color: ModuleColor.space,
                             filled: true, marksLatestPoint: true, endTime: store.snapshot.historyTime,
                             fitsVisibleFractions: true)
                .frame(height: 24)
                .modifier(HomeActivityGlow(active: memoryHovered, color: ModuleColor.space))
                .accessibilityHidden(true)
            if let memory = metrics.memory {
                let used = humanSize(memory.used)
                let swap = memory.swapUsed.map { humanSize($0) }
                detail("\(used) · \(swap.map { "\($0) swap" } ?? "swap indisponible")")
                    .accessibilityLabel("Mémoire utilisée : \(used). Swap utilisé : \(swap ?? "indisponible").")
            } else {
                detail("Mémoire indisponible")
            }
        }
        .onHover { memoryHovered = $0 }
        .help("La courbe adapte son échelle à la RAM utilisée sur la dernière minute. Le swap indique l’espace disque utilisé comme mémoire virtuelle.")
        .accessibilityElement(children: .combine)
    }

    private var disk: some View {
        Button(action: onStorage) {
            HomeActivityTile(alignsWithBattery: wide) {
                metricHeader(availableWidth < 960 ? "Disque" : "Espace libre", symbol: "internaldrive") {
                    badge(storage.map { humanSize($0.total, fractionalAbove: 1_000_000_000) } ?? "—")
                }
            } value: {
                let size = storage.map { humanSizeParts($0.available, fractionalAbove: 1_000_000_000) }
                reading(size?.value, unit: size?.unit ?? "")
                    .accessibilityLabel(storage.map { "Stockage libre : \(humanSize($0.available, fractionalAbove: 1_000_000_000))" } ?? "Stockage indisponible")
            } footer: {
                let barColor = storage?.homeBarColor ?? .clear
                usageBar(storage?.fraction, color: barColor, height: 7)
                    .modifier(HomeActivityGlow(active: diskHovered && storage != nil, color: barColor))
                detail(storage.map { "\(humanSize($0.used, fractionalAbove: 1_000_000_000)) utilisés · \($0.percent) %" } ?? "Mesure indisponible")
            }
        }
        .buttonStyle(HomeActivityMetricButtonStyle())
        .onHover { diskHovered = $0 }
        .help("Stockage interne : espace disponible pour un usage important selon macOS, espace purgeable compris.")
        .accessibilityElement(children: .combine).accessibilityHint("Ouvrir Espace disque")
    }

    private var network: some View {
        HomeActivityTile(alignsWithBattery: wide) {
            metricHeader("Réseau", symbol: wifi?.symbol ?? "network") {
                badge(wifi?.connected == true ? wifi?.kind.rawValue ?? "—" : "Hors ligne")
            }
        } value: {
            reading(wifi?.received.map { NetworkRateFormat.value($0) }, unit: "Mb/s", symbol: "arrow.down")
                .transaction { $0.animation = nil }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Réception : \(NetworkRateFormat.megabits(wifi?.received))")
        } footer: {
            TrayHistoryChart(points: wifi?.connected == true ? networkPoints : [], color: ModuleColor.space,
                             maximum: store.snapshot.networkScale.maximum, filled: true, endTime: store.snapshot.historyTime)
                .frame(height: 24).modifier(HomeActivityGlow(active: networkHovered, color: ModuleColor.space))
                .accessibilityHidden(true)
            let upload = detail("↑ \(NetworkRateFormat.megabits(wifi?.sent))")
                .accessibilityLabel("Envoi : \(NetworkRateFormat.megabits(wifi?.sent))")
            let address = detail(wifi?.connected == true ? wifi?.address ?? "IP indisponible" : "Aucune liaison active")
                .truncationMode(.middle)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { upload.fixedSize(); Spacer(minLength: 0); address.fixedSize() }
                VStack(alignment: .leading, spacing: 2) { upload; address }
            }
        }
        .onHover { networkHovered = $0 }
        .help("\(wifi?.address ?? "IP indisponible") · \(wifi?.interface ?? "")\nTrafic de l’interface principale, réseau local compris. Ce débit n’est pas un test de vitesse Internet.")
        .accessibilityElement(children: .combine)
    }

    private var fans: some View {
        HomeActivityTile(alignsWithBattery: wide) {
            metricHeader("Ventilateurs", symbol: "fanblades") {
                badge(metrics.fans?.load.map { "\(Int(($0 * 100).rounded())) %" } ?? "—")
                    .accessibilityLabel(metrics.fans?.load.map { "Vitesse relative maximale : \(Int(($0 * 100).rounded())) %" } ?? "Vitesse relative indisponible")
            }
        } value: {
            reading(metrics.fans?.fastest.map { String(Int($0.rounded())) }, unit: "tr/min")
        } footer: {
            HomeFanControls(fans: metrics.fans)
        }
        .help(metrics.fans?.description ?? "Lecture des ventilateurs indisponible")
    }

    private func reading(_ value: String?, unit: String, symbol: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.caption2).accessibilityHidden(true) }
            Text(value ?? "—").font(.system(size: 32, weight: .semibold))
            if value != nil { Text(unit).font(AppFont.caption.weight(.semibold)).foregroundStyle(Theme.muted) }
        }
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }

    private func metricHeader<Badge: View>(_ title: String, symbol: String, @ViewBuilder badge: () -> Badge) -> some View {
        let label = HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10)).accessibilityHidden(true)
            Text(title).textCase(.uppercase).font(AppFont.body.weight(.semibold))
        }
        .foregroundStyle(Theme.muted)
        .fixedSize()

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                label
                Spacer(minLength: 0)
                badge().fixedSize()
            }
            VStack(alignment: .leading, spacing: 3) {
                label
                badge()
            }
        }
    }

    private func badge(_ title: String, color: Color = Theme.muted) -> some View {
        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(color).monospacedDigit()
            .lineLimit(1).padding(.horizontal, 5).padding(.vertical, 2)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
    }
    private func detail(_ text: String) -> some View {
        Text(text).font(AppFont.caption).foregroundStyle(Theme.muted).lineLimit(1)
    }
    private func usageBar(_ fraction: Double?, color: Color, height: CGFloat = 5) -> some View {
        GeometryReader { geometry in
            Capsule().fill(.white.opacity(0.08)).overlay(alignment: .leading) {
                Capsule().fill(color).frame(width: geometry.size.width * min(1, max(0, fraction ?? 0)))
            }
        }.frame(height: height).frame(height: 20).accessibilityHidden(true)
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

extension TrayStorageUsage {
    var homeBarColor: Color {
        switch percent {
        case 90...: return .red
        case 70...: return .orange
        default: return ModuleColor.space
        }
    }
}

/// The tallest card sets the height of every row at the actual column widths.
private struct HomeCardGrid: Layout {
    let width: CGFloat
    let wide: Bool
    private let gap: CGFloat = 12
    private var columns: Int { wide ? 4 : 2 }
    private var leadingWidth: CGFloat { wide ? max(244, width * 0.295) : (width - gap) / 2 }
    private var metricWidth: CGFloat { (width - leadingWidth - CGFloat(columns - 1) * gap) / CGFloat(columns - 1) }

    private func columnWidth(_ index: Int) -> CGFloat {
        index.isMultiple(of: columns) ? leadingWidth : metricWidth
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.enumerated().map { index, card in
            card.sizeThatFits(.init(width: columnWidth(index), height: nil)).height
        }.max() ?? 0
        let rows = (subviews.count + columns - 1) / columns
        return CGSize(width: width, height: height * CGFloat(rows) + gap * CGFloat(max(0, rows - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = (subviews.count + columns - 1) / columns
        guard rows > 0 else { return }
        let height = (bounds.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        for (index, card) in subviews.enumerated() {
            let column = index % columns
            let x = column == 0 ? 0 : leadingWidth + gap + CGFloat(column - 1) * (metricWidth + gap)
            let y = CGFloat(index / columns) * (height + gap)
            card.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading,
                       proposal: .init(width: columnWidth(index), height: height))
        }
    }
}
