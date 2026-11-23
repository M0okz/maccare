import SwiftUI

struct AboutSidebarButton: View {
    let selected: Bool
    let compact: Bool
    let updateAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SidebarLabel(title: "À propos", symbol: "info.circle", compact: compact)
        }
        .buttonStyle(SidebarRowStyle(selected: selected))
        .overlay {
            if updateAvailable {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.updateAttention, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: compact ? .topTrailing : .trailing) {
            if updateAvailable {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.body).foregroundStyle(Theme.updateAttention)
                    .padding(.top, compact ? 4 : 0).padding(.trailing, compact ? 8 : 12)
                    .accessibilityHidden(true).allowsHitTesting(false)
            }
        }
        .accessibilityLabel("À propos")
        .accessibilityValue(updateAvailable ? "Mise à jour disponible" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(updateAvailable ? "À propos · mise à jour disponible" : "À propos")
    }
}
