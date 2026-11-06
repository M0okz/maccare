import SwiftUI

struct TrayTileStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(hovered ? 0.10 : 0.055), in: RoundedRectangle(cornerRadius: TrayAppearance.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: TrayAppearance.cardRadius).strokeBorder(.white.opacity(hovered ? 0.18 : 0.09)))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .pressFeedback(configuration.isPressed, scale: 0.98)
            .onHover { hovered = $0 }
    }
}
