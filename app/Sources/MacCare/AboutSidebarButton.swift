import SwiftUI

struct AboutSidebarButton: View {
    let selected: Bool
    let compact: Bool
    let updateAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "info.circle")
                    .font(AppFont.emphasis)
                    .foregroundStyle(selected ? Color.white : Theme.muted)
                    .frame(width: compact ? 24 : 20, height: 20)
                    .accessibilityHidden(true)
                if !compact {
                    Text("À propos").font(AppFont.body.weight(.medium)).foregroundStyle(Theme.fg)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, compact ? 0 : 24).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            .contentShape(Rectangle())
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
