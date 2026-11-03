import SwiftUI

/// Même composition pour les rubriques : dégradé profond et lumière douce dans la même teinte.
struct CategoryBackground: View {
    let section: NavigationSection
    private var palette: CategoryPalette { section.palette }

    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.base, palette.middle, palette.edge],
                           startPoint: .bottomLeading, endPoint: .topTrailing)
            if section == .files {
                RadialGradient(colors: [palette.accent.opacity(0.25), .clear],
                               center: .center, startRadius: 20, endRadius: 560)
            } else {
                RadialGradient(colors: [palette.middle.opacity(0.5), .clear],
                               center: UnitPoint(x: 0.55, y: 0.4), startRadius: 20, endRadius: 650)
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
