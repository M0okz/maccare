import SwiftUI

struct HomeHealthCard<ScanAction: View>: View {
    @ObservedObject var store: TrayMetricsStore
    @ObservedObject var battery: BatteryModel
    let storage: TrayStorageUsage?
    @ViewBuilder let scanAction: () -> ScanAction
    @State private var showingDetails = false
    private var presentation: HomeHealthPresentation {
        .init(storage: storage, pressure: store.snapshot.display.memory?.pressure,
              thermal: ProcessInfo.processInfo.thermalState, battery: battery.snapshot)
    }

    var body: some View {
        HealthCardLayout {
            Button { showingDetails = true } label: {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 5) {
                        Label("Santé du Mac", systemImage: "waveform.path.ecg")
                            .font(AppFont.secondary.weight(.semibold)).foregroundStyle(Theme.ok)
                        Image(systemName: "info.circle").font(.caption).foregroundStyle(Theme.muted)
                            .accessibilityHidden(true)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            score
                            status.fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 2) { score; status }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plainAction)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Afficher les critères de santé du Mac")
            .help("Voir les mesures et le calcul de la santé du Mac.")
            .popover(isPresented: $showingDetails, arrowEdge: .trailing) {
                MacHealthDetails(assessment: presentation.assessment)
            }
            Text(presentation.detail).font(AppFont.secondary).foregroundStyle(Theme.muted)
                .lineLimit(1).minimumScaleFactor(0.85)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(MacSystemSpecs.uptime(now: context.date))
                    .font(AppFont.secondary).foregroundStyle(Theme.muted).monospacedDigit()
            }
            scanAction()
        }
        .modifier(HomeStatusCardStyle(tint: Theme.ok))
    }

    private var score: some View {
        Text(presentation.assessment.percent.map(String.init) ?? "—")
            .font(.system(size: 34, weight: .semibold)).monospacedDigit().fixedSize()
            .accessibilityLabel(presentation.assessment.percent.map { "Indice de santé, \($0) sur 100" } ?? "Indice en attente")
    }

    private var status: some View {
        Text(presentation.title).font(AppFont.secondary.weight(.semibold)).foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch presentation.state {
        case .healthy: return Theme.ok
        case .watch: return Theme.warn
        case .check: return Theme.danger
        case .reading, .partial: return Theme.muted
        }
    }
}

/// The action aligns to the whole card. A long summary can use the space below it.
private struct HealthCardLayout: Layout {
    private let gap: CGFloat = 6

    private func measurements(width: CGFloat, subviews: Subviews) -> (leading: CGFloat, summaryBelow: Bool, sizes: [CGSize]) {
        let action = subviews[3].sizeThatFits(.unspecified)
        let leading = max(0, width - action.width - 8)
        let summaryBelow = subviews[1].sizeThatFits(.unspecified).width > leading
        let sizes = [
            subviews[0].sizeThatFits(.init(width: leading, height: nil)),
            subviews[1].sizeThatFits(.init(width: summaryBelow ? width : leading, height: nil)),
            subviews[2].sizeThatFits(.init(width: width, height: nil)),
            action
        ]
        return (leading, summaryBelow, sizes)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let idealWidth = subviews[0].sizeThatFits(.unspecified).width + 8 + subviews[3].sizeThatFits(.unspecified).width
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth
        let (_, below, sizes) = measurements(width: width, subviews: subviews)
        let footer = sizes[1].height + gap + sizes[2].height
        let textHeight = sizes[0].height + gap + footer
        let actionHeight = sizes[3].height + (below ? 2 * (gap + footer) : 0)
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? 0
        return CGSize(width: width, height: max(textHeight, actionHeight, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (leading, below, sizes) = measurements(width: bounds.width, subviews: subviews)
        let action = sizes[3]
        let scoreBottom = bounds.minY + sizes[0].height
        let footerTop = bounds.maxY - sizes[2].height
        let centeredSummaryY = (scoreBottom + footerTop - sizes[1].height) / 2
        let summaryY = max(centeredSummaryY, below ? bounds.midY + action.height / 2 + gap : scoreBottom + gap)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: .init(width: leading, height: nil))
        subviews[1].place(at: .init(x: bounds.minX, y: summaryY), anchor: .topLeading,
                          proposal: .init(width: below ? bounds.width : leading, height: nil))
        subviews[2].place(at: .init(x: bounds.minX, y: bounds.maxY), anchor: .bottomLeading,
                          proposal: .init(width: bounds.width, height: nil))
        subviews[3].place(at: .init(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: .unspecified)
    }
}
