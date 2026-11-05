import SwiftUI

/// Un accès à une rubrique, sans démarrer d’analyse à la navigation.
struct HomeActionCard: View {
    let title: String
    let detail: String
    let actionTitle: String
    let symbol: String
    let color: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ModuleIcon(symbol: symbol, color: color, size: 38).accessibilityHidden(true)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.body.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65)).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(detail).font(AppFont.secondary).foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(18).frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(HomeShortcutStyle(color: color, hovering: hovering))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityHint(actionTitle)
    }
}

private struct HomeShortcutStyle: ButtonStyle {
    let color: Color
    let hovering: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(LinearGradient(colors: [color.opacity(hovering ? 0.28 : 0.19), color.opacity(0.07)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(hovering ? 0.22 : 0.1)))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .pressFeedback(configuration.isPressed, scale: 0.985)
    }
}
