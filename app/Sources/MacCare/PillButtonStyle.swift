import SwiftUI

/// Styles the label of a native Button, including its full hit area.
struct PillButtonStyle: ButtonStyle {
    enum Emphasis { case secondary, selected, prominent }

    var emphasis: Emphasis = .secondary
    var maximumWidth: CGFloat?
    var minimumHitHeight: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, emphasis: emphasis, maximumWidth: maximumWidth, minimumHitHeight: minimumHitHeight)
    }

    private struct Face: View {
        let configuration: Configuration
        let emphasis: Emphasis
        let maximumWidth: CGFloat?
        let minimumHitHeight: CGFloat?
        @Environment(\.controlSize) private var controlSize
        @Environment(\.keyboardShortcut) private var shortcut
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused
        @Environment(\.colorSchemeContrast) private var contrast
        @State private var hovered = false

        private var metrics: (height: CGFloat, inset: CGFloat, font: Font) {
            switch controlSize {
            case .mini: return (24, 8, .callout)
            case .small: return (26, 10, .callout)
            case .large: return (40, 18, AppFont.body)
            default: return (32, 13, .body)
            }
        }

        private var foreground: Color {
            if emphasis == .prominent { return .white }
            if configuration.role == .destructive { return Theme.destructiveInk }
            return emphasis == .selected ? Theme.fg : Theme.muted
        }

        private var outline: Color {
            if focused && enabled { return .accentColor }
            if contrast == .increased { return foreground }
            if emphasis == .selected || shortcut == .defaultAction { return Theme.accentInk.opacity(0.55) }
            return .clear
        }

        var body: some View {
            configuration.label
                .font(metrics.font.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
                .padding(.horizontal, metrics.inset)
                .padding(.vertical, 3)
                .frame(maxWidth: maximumWidth, minHeight: metrics.height)
                .background {
                    switch emphasis {
                    case .secondary: Capsule().fill(Theme.fg.opacity(0.09))
                    case .selected: Capsule().fill(Theme.accent.opacity(0.28))
                    case .prominent:
                        if configuration.role == .destructive {
                            Capsule().fill(Theme.danger)
                        } else {
                            Capsule().fill(.tint)
                        }
                        Capsule().fill(.black.opacity(0.22))
                    }
                }
                .overlay {
                    Capsule().fill(Theme.fg.opacity(configuration.isPressed ? 0.14 : (hovered && enabled ? 0.07 : 0)))
                    Capsule().strokeBorder(outline, lineWidth: focused ? 2 : 1)
                }
                .frame(minHeight: minimumHitHeight)
                .contentShape(Capsule())
                .opacity(enabled ? 1 : 0.48)
                .pressFeedback(enabled && configuration.isPressed)
                .onHover { hovered = $0 }
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var actionPill: Self { Self() }
    static var toolbarPill: Self { Self(minimumHitHeight: 44) }
    static var prominentPill: Self { Self(emphasis: .prominent) }
}
