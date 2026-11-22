import SwiftUI

struct HomeActivityTile<Header: View, Value: View, Footer: View>: View {
    @ViewBuilder let header: () -> Header
    @ViewBuilder let value: () -> Value
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        ActivityTileLayout {
            header()
            value()
            VStack(alignment: .leading, spacing: 6, content: footer)
        }
        .modifier(HomeStatusCardStyle(tint: Theme.accent))
        .contentShape(RoundedRectangle(cornerRadius: Radius.card))
    }
}

/// Keep the reading on the card's centerline, even when adjacent footers have different heights.
private struct ActivityTileLayout: Layout {
    private let gap: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let sizes = subviews.map { $0.sizeThatFits(.init(width: width, height: nil)) }
        let minimum = sizes.reduce(2 * gap) { $0 + $1.height }
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? minimum
        return CGSize(width: width ?? sizes.map(\.width).max() ?? 0, height: max(minimum, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let fit = ProposedViewSize(width: bounds.width, height: nil)
        let header = subviews[0], value = subviews[1], footer = subviews[2]
        let first = bounds.minY + header.sizeThatFits(fit).height + gap
        let valueHeight = value.sizeThatFits(fit).height
        let footerY = bounds.maxY - footer.sizeThatFits(fit).height
        let center = bounds.midY - valueHeight / 2
        let valueY = max(first, min(center, footerY - gap - valueHeight))
        header.place(at: bounds.origin, anchor: .topLeading, proposal: fit)
        value.place(at: CGPoint(x: bounds.minX, y: valueY), anchor: .topLeading, proposal: fit)
        footer.place(at: CGPoint(x: bounds.minX, y: footerY), anchor: .topLeading, proposal: fit)
    }
}
