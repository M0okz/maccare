import SwiftUI

struct HomeHealthCard: View {
    @ObservedObject var store: TrayMetricsStore
    @ObservedObject var battery: BatteryModel
    let storage: TrayStorageUsage?
    @State private var showingDetails = false
    @ScaledMetric(relativeTo: .title) private var statusSize = 24
    @ScaledMetric(relativeTo: .body) private var iconColumn: CGFloat = 18
    private let machineName = Host.current().localizedName ?? MacHardwarePresentation.current.title
    private var presentation: HomeHealthPresentation {
        .init(storage: storage, pressure: store.snapshot.display.memory?.pressure,
              thermal: ProcessInfo.processInfo.thermalState, battery: battery.snapshot)
    }

    var body: some View {
        Button { showingDetails = true } label: {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow(alignment: .firstTextBaseline) {
                    Image(systemName: "waveform.path.ecg").font(.headline)
                        .foregroundStyle(Theme.accentInk).frame(width: iconColumn).accessibilityHidden(true)
                    Text("Santé du Mac").font(.headline).accessibilityAddTraits(.isHeader)
                }
                GridRow {
                    Color.clear.frame(width: iconColumn, height: 0).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(presentation.title).font(.system(size: statusSize, weight: .semibold)).foregroundStyle(statusColor)
                        Text(presentation.detail).font(AppFont.secondary).foregroundStyle(Theme.muted)
                            .lineLimit(1).help(presentation.detail)
                    }
                }
                GridRow(alignment: .top) {
                    Image(systemName: machineSymbol).font(.title3).foregroundStyle(Theme.muted)
                        .frame(width: iconColumn).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(machineName).font(AppFont.emphasis).lineLimit(1).help(machineName)
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text(specs(now: context.date))
                                .font(AppFont.caption).foregroundStyle(Theme.muted).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.85)
                                .help("\(MacSystemSpecs.ram) · \(MacSystemSpecs.systemVersion) · \(MacSystemSpecs.uptime(now: context.date))")
                                .accessibilityLabel("\(MacSystemSpecs.ram), \(MacSystemSpecs.systemVersion), \(MacSystemSpecs.uptime(now: context.date))")
                        }
                    }
                }
            }
        }
        .buttonStyle(HomeStatusCardButtonStyle(tint: Theme.accent))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Afficher les critères de santé du Mac")
        .help("Voir les mesures et le calcul de la santé du Mac.")
        .popover(isPresented: $showingDetails, arrowEdge: .trailing) {
            MacHealthDetails(assessment: presentation.assessment)
        }
    }

    private func specs(now: Date) -> String {
        let uptime = MacSystemSpecs.bootDate.map { MacSystemSpecs.duration(now.timeIntervalSince($0)) } ?? "—"
        return "\(MacSystemSpecs.ram) · \(MacSystemSpecs.systemVersion) · ↑ \(uptime)"
    }

    private var statusColor: Color {
        switch presentation.state {
        case .healthy: return Theme.ok
        case .watch: return Theme.warn
        case .check: return Theme.danger
        case .reading, .partial: return Theme.muted
        }
    }

    private var machineSymbol: String {
        switch MacHardwarePresentation.current.family {
        case .pro13, .proNotched, .airClassic, .airNotched, .laptop: return "laptopcomputer"
        default: return "desktopcomputer"
        }
    }
}
