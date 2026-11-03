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
        }.buttonStyle(.plain).foregroundStyle(Theme.muted)
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
}


/// La surface change au survol, jamais la position ni la taille du libellé.
struct ToolbarActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToolbarActionSurface(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct ToolbarActionSurface<Label: View>: View {
    let label: Label
    let pressed: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        label.font(AppFont.body.weight(.semibold))
            .padding(.horizontal, 10).frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(enabled && (hovered || pressed) ? (colorScheme == .dark ? 0.16 : 0.55) : 0))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder((colorScheme == .dark ? Color.white : Color.black)
                                .opacity(enabled && (hovered || pressed) ? (colorScheme == .dark ? 0.14 : 0.06) : 0), lineWidth: 0.5)
                    }
            }
            .frame(minHeight: 44).contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }
}
