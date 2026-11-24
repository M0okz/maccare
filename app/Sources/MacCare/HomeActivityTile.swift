import SwiftUI

extension VerticalAlignment {
    private enum ReadingBaseline: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[.firstTextBaseline]
        }
    }
    static let homeReadingBaseline = Self(ReadingBaseline.self)
}

struct HomeActivityTile<Header: View, Value: View, Footer: View>: View {
    var alignsWithBattery = false
    @ViewBuilder let header: () -> Header
    @ViewBuilder let value: () -> Value
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        ActivityTileLayout(alignsWithBattery: alignsWithBattery) {
            header()
            value()
            VStack(alignment: .leading, spacing: 6, content: footer)
        }
        .modifier(HomeStatusCardStyle(tint: Theme.accent))
        .contentShape(RoundedRectangle(cornerRadius: Radius.card))
    }
}

/// The battery row shares a text baseline across readings drawn at different font sizes.
struct ActivityTileLayout: Layout {
    let alignsWithBattery: Bool
    private let gap: CGFloat = 6
    private let batteryBaselineFromCenter: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let sizes = subviews.map { $0.dimensions(in: .init(width: width, height: nil)) }
        let minimum: CGFloat
        if alignsWithBattery {
            let baseline = sizes[1][VerticalAlignment.homeReadingBaseline]
            let above = sizes[0].height + gap + baseline - batteryBaselineFromCenter
            let below = sizes[2].height + gap + sizes[1].height - baseline + batteryBaselineFromCenter
            minimum = 2 * max(above, below)
        } else {
            minimum = sizes.reduce(2 * gap) { $0 + $1.height }
        }
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? minimum
        return CGSize(width: width ?? sizes.map(\.width).max() ?? 0, height: max(minimum, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let fit = ProposedViewSize(width: bounds.width, height: nil)
        let header = subviews[0], value = subviews[1], footer = subviews[2]
        let first = bounds.minY + header.sizeThatFits(fit).height + gap
        let valueSize = value.dimensions(in: fit)
        let footerY = bounds.maxY - footer.sizeThatFits(fit).height
        let target = alignsWithBattery
            ? bounds.midY + batteryBaselineFromCenter - valueSize[VerticalAlignment.homeReadingBaseline]
            : bounds.midY - valueSize.height / 2
        let valueY = max(first, min(target, footerY - gap - valueSize.height))
        header.place(at: bounds.origin, anchor: .topLeading, proposal: fit)
        value.place(at: CGPoint(x: bounds.minX, y: valueY), anchor: .topLeading, proposal: fit)
        footer.place(at: CGPoint(x: bounds.minX, y: footerY), anchor: .topLeading, proposal: fit)
    }
}
