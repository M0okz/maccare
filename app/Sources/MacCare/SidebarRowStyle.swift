import SwiftUI

struct SidebarRowStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SidebarRowSurface(label: configuration.label, selected: selected, pressed: configuration.isPressed)
    }
}

private struct SidebarRowSurface<Label: View>: View {
    let label: Label
    let selected: Bool
    let pressed: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var highlighted: Bool { enabled && hovered }

    var body: some View {
        label
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.13 : (highlighted ? 0.08 : 0)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(selected ? 0.08 : (highlighted ? 0.04 : 0)), lineWidth: 0.5)
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: highlighted)
            }
            .opacity(pressed ? 0.9 : 1)
            .pressFeedback(pressed && enabled)
            .onHover { hovered = $0 }
    }
}
