import SwiftUI

/// Bas des écrans d'accueil de rubrique : l'action principale garde la même position d'une rubrique
/// à l'autre, quel que soit le contenu placé sous elle.
struct OverviewActionFooter<Action: View, Secondary: View>: View {
    let caption: String
    var message: String? = nil
    @ViewBuilder let action: Action
    @ViewBuilder let secondary: Secondary

    var body: some View {
        VStack(spacing: 12) {
            action
            Text(caption).font(AppFont.secondary).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            if let message {
                Text(message).font(AppFont.secondary).foregroundStyle(Theme.warn)
                    .multilineTextAlignment(.center)
            }
            secondary
        }
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .top)
        .padding(.horizontal, 24).padding(.bottom, 24)
    }
}

extension OverviewActionFooter where Secondary == EmptyView {
    init(caption: String, message: String? = nil, @ViewBuilder action: () -> Action) {
        self.init(caption: caption, message: message, action: action, secondary: { EmptyView() })
    }
}

/// Ligne de présentation d'une rubrique : même icône, même texte et même alignement partout.
struct OverviewFeatureRow: View {
    let symbol: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 22))
                .foregroundStyle(tint).frame(width: 30).accessibilityHidden(true)
            Text(title).font(.system(size: 16, weight: .medium))
        }
    }
}

/// Carte de la page Batterie. Ses boutons reprennent le style secondaire du reste de l'application.
struct BatterySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            content
        }
        .buttonStyle(SecondaryActionButtonStyle())
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.card))
    }
}
