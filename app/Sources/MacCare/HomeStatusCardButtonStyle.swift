import SwiftUI

struct HomeStatusCardButtonStyle: ButtonStyle {
    let tint: Color
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(HomeStatusCardStyle(tint: tint))
            .contentShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(
                .white.opacity(enabled && focused ? 0.8 : 0), lineWidth: 2))
            .opacity(!enabled ? 0.45 : (configuration.isPressed ? 0.85 : 1))
            .pressFeedback(configuration.isPressed && enabled, scale: 0.985)
    }
}
