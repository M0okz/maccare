import SwiftUI

/// Même composition que le gestionnaire Performances : navigateur, détail et actions fixes.
struct ManagerBrowserLayout<Browser: View, Detail: View, Footer: View>: View {
    @ViewBuilder let browser: () -> Browser
    @ViewBuilder let detail: () -> Detail
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ScrollView {
                        browser().fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    }
                    .frame(width: max(240, min(310, geometry.size.width * 0.28)))
                    Divider()
                    VStack(spacing: 0) { detail() }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            footer()
        }
    }
}
