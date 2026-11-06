import SwiftUI

struct TrayActionStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, prominent ? 12 : 8).frame(minHeight: 28)
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.4))
            .background {
                RoundedRectangle(cornerRadius: TrayAppearance.controlRadius).fill(LinearGradient(colors: prominent ? [Color(hex: "#AB64F4"), Color(hex: "#793BE0")] : [.white.opacity(hovered ? 0.10 : 0.055), .white.opacity(0.035)], startPoint: .top, endPoint: .bottom))
            }
            .overlay(RoundedRectangle(cornerRadius: TrayAppearance.controlRadius).strokeBorder(.white.opacity(prominent ? 0.22 : 0.10)))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .pressFeedback(configuration.isPressed && enabled)
            .onHover { hovered = $0 }
    }
}
