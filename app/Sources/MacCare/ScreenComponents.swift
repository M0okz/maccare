import SwiftUI

/// Le titre reste centré dans la zone de contenu, indépendamment de la largeur des actions.
struct ScreenToolbar<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 16) { leading(); Spacer(minLength: 16); trailing() }
            .frame(minHeight: 32)
            .overlay {
                Text(title).font(AppFont.body.weight(.semibold)).lineLimit(1)
                    .accessibilityAddTraits(.isHeader).allowsHitTesting(false)
            }
    }
}

/// Les actions passent sur une seconde ligne plutôt que de comprimer le bilan ou déborder.
struct AdaptiveActionRow<Summary: View, Actions: View>: View {
    @ViewBuilder let summary: () -> Summary
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) { summary().fixedSize(horizontal: true, vertical: false); Spacer(minLength: 12); actions().fixedSize(horizontal: true, vertical: false) }
            VStack(alignment: .leading, spacing: 12) {
                summary().frame(maxWidth: .infinity, alignment: .leading)
                HStack { Spacer(minLength: 0); actions() }
            }
        }
    }
}

struct InterfaceHelp: View {
    let title: String
    let message: String
    @State private var presented = false

    var body: some View {
        Button { presented.toggle() } label: {
            Label(title, systemImage: "info.circle").font(AppFont.secondary)
        }.buttonStyle(.actionPill).controlSize(.small)
            .popover(isPresented: $presented, arrowEdge: .leading) {
                Text(message).font(AppFont.body).fixedSize(horizontal: false, vertical: true)
                    .padding(20).frame(width: 360)
            }
    }
}


/// Cadre commun aux gestionnaires de fichiers et d’applications : un panneau dans la fenêtre.
struct ManagerPanelStyle: ViewModifier {
    var accent: Color = Theme.accent
    var background: Color = Theme.window
    func body(content: Content) -> some View {
        content.font(AppFont.body).foregroundStyle(Theme.fg).background(Color.white)
            .environment(\.colorScheme, .light).tint(accent)
            .clipShape(RoundedRectangle(cornerRadius: 16)).padding(8).background(background)
    }
}

enum ManagerPanelMotion {
    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity
    }

    /// Changement de rubrique : l'ancienne page ne reste pas visible sous la nouvelle.
    /// Le fond de catégorie, lui, assure la continuité de couleur.
    static func page(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .asymmetric(insertion: .opacity, removal: .identity)
    }
}
