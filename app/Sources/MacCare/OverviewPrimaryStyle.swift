import SwiftUI

/// Une action principale ample ; appui visible sans animation ni modification de la sémantique du bouton.
struct OverviewPrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 26).padding(.vertical, 14)
            .frame(minHeight: 48)
            .background(
                LinearGradient(colors: [ModuleColor.space, Theme.accent.shade(-0.15)],
                               startPoint: .leading, endPoint: .trailing),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25)))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
