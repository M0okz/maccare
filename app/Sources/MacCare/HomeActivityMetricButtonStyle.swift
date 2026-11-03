import SwiftUI

struct HomeActivityMetricButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.fg)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                .white.opacity(enabled && focused ? 0.8 : 0), lineWidth: 2))
            .opacity(!enabled ? 0.45 : (configuration.isPressed ? 0.8 : 1))
    }
}
