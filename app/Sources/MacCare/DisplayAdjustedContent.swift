import SwiftUI

struct DisplayAdjustedContent: ViewModifier {
    let layout: MainWindowLayout

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let size = layout.contentSize(in: geometry.size)
            content
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .scaleEffect(layout.scale, anchor: .topLeading)
        }
        .animation(nil, value: layout)
    }
}

/// Mesure chaque bloc en points logiques et réserve sa taille affichée dans la page.
private struct ScaledBlockLayout: Layout {
    let scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let block = subviews.first else { return .zero }
        let logical = ProposedViewSize(width: proposal.width.map { $0 / scale },
                                       height: proposal.height.map { $0 / scale })
        let measured = block.sizeThatFits(logical)
        return CGSize(width: measured.width * scale, height: measured.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width / scale, height: bounds.height / scale))
    }
}

extension View {
    func dashboardBlockScale(_ scale: CGFloat) -> some View {
        ScaledBlockLayout(scale: scale) { self.scaleEffect(scale, anchor: .topLeading) }
    }
}
