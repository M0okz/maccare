import SwiftUI

/// Surface secondaire commune : le survol change le contraste sans déplacer le contrôle.
struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryActionSurface(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct SecondaryActionSurface<Label: View>: View {
    let label: Label
    let pressed: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.colorScheme) private var scheme
    @Environment(\.controlSize) private var size
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorContrast

    private var dark: Bool { scheme == .dark }
    private var emphasized: Bool { enabled && (hovered || pressed) }
    private var height: CGFloat {
        switch size {
        case .large: return 40
        case .small: return 28
        case .mini: return 24
        default: return 32
        }
    }
    private var fillOpacity: Double {
        guard enabled else { return dark ? 0.06 : 0.025 }
        if pressed { return dark ? 0.33 : 0.15 }
        return dark ? (hovered ? 0.27 : 0.13) : (hovered ? 0.1 : 0.045)
    }
    private var ink: Color { dark ? .white : .black }

    var body: some View {
        label
            .font(AppFont.body.weight(.semibold))
            .foregroundStyle(ink.opacity(enabled ? (dark ? 1 : 0.85) : 0.4))
            .padding(.horizontal, size == .large ? 18 : 12)
            .frame(minHeight: height)
            .background(ink.opacity(fillOpacity), in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(focused && enabled ? Color.accentColor : ink.opacity(
                        colorContrast == .increased ? 0.5 : (emphasized ? 0.3 : (dark ? 0.18 : 0.12))),
                                  lineWidth: focused && enabled ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 11))
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }
}
