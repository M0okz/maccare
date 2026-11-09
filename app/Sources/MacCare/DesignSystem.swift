import SwiftUI
import AppKit

// MARK: - Couleurs de base

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = CGFloat((v & 0xFF0000) >> 16) / 255
        let g = CGFloat((v & 0x00FF00) >> 8) / 255
        let b = CGFloat(v & 0x0000FF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

extension Color {
    init(hex: String) { self.init(nsColor: NSColor(hex: hex)) }

    /// Couleur qui suit le thème clair/sombre du système et un choix explicite.
    static func themed(_ light: String, _ dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark0 = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: dark0 ? dark : light)
        })
    }

    /// Variante plus claire (amount > 0) ou plus sombre (amount < 0), pour les dégradés.
    func shade(_ amount: CGFloat) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.gray
        let f = max(-1, min(1, amount))
        func adj(_ v: CGFloat) -> CGFloat { f >= 0 ? v + (1 - v) * f : v * (1 + f) }
        return Color(nsColor: NSColor(srgbRed: adj(base.redComponent),
                                      green: adj(base.greenComponent),
                                      blue: adj(base.blueComponent),
                                      alpha: base.alphaComponent))
    }
}

// MARK: - Jetons de thème (palette vivante)

enum Theme {
    // Palette sombre violet et prune de MacCare.
    static let bg        = Color.themed("#F2F0F8", "#140C29")
    static let window    = Color.themed("#F7F6FB", "#190F33")
    /// Teinte haute du fond de la fenêtre, pour une lueur en dégradé vertical.
    static let windowTop = Color.themed("#FFFFFF", "#2C1B52")
    static let sidebar   = Color.themed("#ECEAF4", "#0E0820")
    static let surface   = Color.themed("#FFFFFF", "#241745")
    static let fg        = Color.themed("#1C172E", "#FFFFFF")
    static let muted     = Color.themed("#6B6388", "#E0D9EE")
    static let faint     = Color.themed("#8E85AC", "#BFB1D6")
    static let border    = Color.themed("#E0DCEC", "#392C66")
    static let hairline  = Color.themed("#EAE7F3", "#2C2150")
    static let accent    = Color.themed("#7C4DFF", "#9D6CFF")
    static let accentInk = Color.themed("#5E34D6", "#C9B3FF")
    static let ok        = Color.themed("#1FA85A", "#49D89A")
    static let warn      = Color.themed("#E0920A", "#F0B23C")
    static let danger    = Color.themed("#DD4B39", "#F0705C")
    /// Rappel global de nouvelle version, lisible sur chaque fond de catégorie.
    static let updateNotice = Color(hex: "#FFD84D")
    static let updateNoticeInk = Color(hex: "#20152E")
}

/// Une couleur par module (identiques en clair et sombre).
enum ModuleColor {
    static let clean     = Color(hex: "#6A5FE0")   // iris (teinte de marque)
    static let space     = Color(hex: "#2F7BF6")
    static let uninstall = Color(hex: "#A855F7")
    static let startup   = Color(hex: "#F08A24")
    static let privacy   = Color(hex: "#4F46E5")
    static let updates   = Color(hex: "#0EA5C4")
    static let maint     = Color(hex: "#E0920A")
}

enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

enum Radius {
    static let card: CGFloat = 14
    static let control: CGFloat = 10
    static let chip: CGFloat = 8
}

// MARK: - Typographie native macOS

/// Police système SF : une échelle lisible, commune aux écrans, listes et actions.
/// Les petits textes restent réservés aux métadonnées ; aucune description en dessous de 14 pt.
enum AppFont {
    static let display = Font.system(size: 40, weight: .regular)
    static let pageTitle = Font.system(size: 32, weight: .semibold)
    static let metric = Font.system(size: 28, weight: .semibold)
    static let section = Font.system(size: 20, weight: .semibold)
    static let emphasis = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 15)
    static let secondary = Font.system(size: 14)
    static let caption = Font.system(size: 13)
}

// MARK: - Composants réutilisables

/// Conteneur « carte » : surface, bordure fine, coins arrondis.
struct CardBackground: ViewModifier {
    var elevated: Bool = false
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .shadow(color: Color.black.opacity(elevated ? 0.13 : 0.05), radius: elevated ? 22 : 10, x: 0, y: elevated ? 12 : 5)
    }
}

extension View {
    func card(elevated: Bool = false) -> some View { modifier(CardBackground(elevated: elevated)) }

    /// Léger soulèvement au survol (profondeur + échelle).
    func hoverLift() -> some View { modifier(HoverLift()) }

    /// Apparition en fondu + léger glissement (délai pour un effet en cascade).
    func appearIn(delay: Double = 0) -> some View { modifier(AppearIn(delay: delay)) }
}

/// Fait apparaître la vue en fondu/glissement à son montage.
struct AppearIn: ViewModifier {
    var delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.1) : Motion.easeOut(0.25).delay(delay)) { shown = true }
            }
    }
}

/// Effet de survol réutilisable : une ombre, sans déplacer le contenu sous le pointeur.
struct HoverLift: ViewModifier {
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .shadow(color: Color.black.opacity(hover ? 0.12 : 0), radius: 18, y: 10)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hover)
            .onHover { hover = $0 }
    }
}

/// Style de bouton avec enfoncement au clic, sans rebond.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.9 : 1)
            .pressFeedback(configuration.isPressed)
    }
}

/// Lien textuel à l'accent de la marque (le style `.link` du système reste bleu).
struct LinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.accentInk)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Nombre interpolé lors d'un changement de valeur sous `withAnimation` (effet compteur).
struct AnimatedNumber: View, Animatable {
    var value: Double
    var format: (Double) -> String
    var font: Font
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View {
        Text(format(value)).font(font).monospacedDigit()
    }
}

/// Icône de module : carré arrondi coloré avec un SF Symbol.
struct ModuleIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(
                LinearGradient(colors: [color.shade(0.18), color.shade(-0.12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: color.shade(-0.35).opacity(0.5), radius: 1, y: 0.5)
            )
            .shadow(color: color.opacity(0.35), radius: size * 0.16, y: size * 0.08)
    }
}

/// Puce sémantique (sûr / à revoir / danger).
struct PillBadge: View {
    enum Kind { case safe, review, danger }
    let text: String
    let kind: Kind

    private var color: Color {
        switch kind {
        case .safe: return Theme.ok
        case .review: return Theme.warn
        case .danger: return Theme.danger
        }
    }

    var body: some View {
        Text(text)
            .font(AppFont.caption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
    }
}

/// Tuile de statistique avec liseré coloré et survol.
struct StatTile: View {
    let title: String
    let value: String
    var unit: String? = nil
    var color: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(AppFont.caption.weight(.semibold)).tracking(0.4)
                .foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(AppFont.metric.weight(.bold))
                    .monospacedDigit()
                if let unit { Text(unit).font(AppFont.secondary.weight(.medium)).foregroundStyle(Theme.muted) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15).padding(.vertical, 13)
        .card()
        .overlay(alignment: .leading) {
            Capsule()
                .fill(LinearGradient(colors: [color.shade(0.15), color], startPoint: .top, endPoint: .bottom))
                .frame(width: 3.5).padding(.vertical, 10)
        }
        .hoverLift()
    }
}

/// Bouton principal avec dégradé d'accent, lueur et enfoncement au clic.
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .font(AppFont.body)
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(
                LinearGradient(colors: [tint.shade(0.1), tint.shade(-0.12)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: tint.opacity(0.35), radius: 8, y: 4)
        }
        .buttonStyle(PressStyle())
    }
}

/// Sélection native : rôle de case à cocher, état et activation clavier fournis par macOS.
struct CheckBox: View {
    let label: String
    let on: Bool
    let toggle: () -> Void

    var body: some View {
        Toggle(label, isOn: Binding(
            get: { on },
            set: { value in if value != on { toggle() } }
        ))
        .toggleStyle(.checkbox)
        .labelsHidden()
        .fixedSize()
    }
}

/// Anneau de santé : se dessine à l'apparition, avec compteur animé et lueur.
struct HealthRing: View {
    let value: Int        // 0–100
    var label: String = "Santé"
    var size: CGFloat = 168

    @State private var shown = false
    private var fraction: CGFloat { CGFloat(max(0, min(100, value))) / 100 }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.hairline, lineWidth: 12)
            Circle()
                .trim(from: 0, to: shown ? fraction : 0)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [ModuleColor.space, Theme.accent, ModuleColor.space]),
                        center: .center, startAngle: .degrees(0), endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.accent.opacity(0.4), radius: 6)
            VStack(spacing: 2) {
                AnimatedNumber(
                    value: shown ? Double(value) : 0,
                    format: { "\(Int($0.rounded()))" },
                    font: .system(size: size * 0.24, weight: .bold)
                )
                Text(label).font(AppFont.secondary).foregroundStyle(Theme.muted)
            }
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.easeOut(duration: 1.0)) { shown = true } }
    }
}

/// Ligne d'élément proposé (partagée nettoyage / désinstalleur).
struct ItemRow: View {
    let item: ScanItem
    let on: Bool
    var why: String = ""
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            CheckBox(label: "Sélectionner \(item.path)", on: on, toggle: toggle)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName).font(AppFont.body)
                Text(item.path)
                    .font(AppFont.caption).foregroundStyle(Theme.faint)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if !why.isEmpty {
                Text(why)
                    .font(AppFont.caption).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Theme.bg, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline))
                    .fixedSize()
            }
            Text(humanSize(item.size_bytes))
                .font(AppFont.body).monospacedDigit().foregroundStyle(Theme.muted)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }
}
