import SwiftUI

/// Même cadre pour les détails du volet ; le défilement garde les actions accessibles.
struct TrayDetailSurface<Content: View>: View {
    let title: String
    var height: CGFloat = 680
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                content()
            }
            .padding(20)
        }
        .frame(width: 390, height: height)
        .foregroundStyle(.white)
        .tint(TrayAppearance.accent)
        .background(LinearGradient(colors: [Color(red: 0.24, green: 0.10, blue: 0.45), Color(red: 0.08, green: 0.03, blue: 0.20)], startPoint: .topTrailing, endPoint: .bottomLeading))
        .preferredColorScheme(.dark)
    }
}
