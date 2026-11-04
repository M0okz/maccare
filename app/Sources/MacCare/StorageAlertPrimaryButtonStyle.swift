import SwiftUI

/// Le bouton reste bleu lorsque l’alerte s’affiche au-dessus d’une autre application.
struct StorageAlertPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Color(nsColor: .systemBlue).opacity(configuration.isPressed ? 0.75 : 1),
                        in: RoundedRectangle(cornerRadius: 6))
    }
}
