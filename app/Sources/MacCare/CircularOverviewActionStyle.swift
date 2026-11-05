import SwiftUI

/// Action de départ des rubriques : cercle identique, couleur propre à chaque catégorie.
struct CircularOverviewActionStyle: ButtonStyle {
    let tint: Color
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 90

    func makeBody(configuration: Configuration) -> some View {
        CircularOverviewActionSurface(label: configuration.label, tint: tint,
                                      diameter: diameter, pressed: configuration.isPressed)
    }
}

private struct CircularOverviewActionSurface<Label: View>: View {
    let label: Label
    let tint: Color
    let diameter: CGFloat
    let pressed: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var emphasized: Bool { enabled && (hovered || focused) }

    var body: some View {
        label
            .font(AppFont.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background {
                Circle()
                    .fill(tint.gradient)
                    .shadow(color: tint.opacity(emphasized ? 0.65 : 0),
                            radius: pressed ? 10 : 18)
            }
            .background {
                Circle()
                    .fill(tint.opacity(emphasized ? 0.2 : 0))
                    .blur(radius: 28)
            }
            .overlay(Circle().fill(.white.opacity(emphasized ? 0.12 : 0)))
            .overlay(Circle().strokeBorder(.white.opacity(emphasized ? 1 : 0.7),
                                          lineWidth: focused && enabled ? 3 : 2))
            .contentShape(Circle())
            .opacity(!enabled ? 0.45 : (pressed ? 0.8 : 1))
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: emphasized)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
            .pressFeedback(pressed && enabled)
    }
}
