import SwiftUI

/// Courbes communes : une attaque franche, sans rebond, pour que l'interface réponde tout de suite.
enum Motion {
    static func easeOut(_ duration: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }
    static func easeInOut(_ duration: Double) -> Animation { .timingCurve(0.77, 0, 0.175, 1, duration: duration) }
    static let press = easeOut(0.14)
}

/// Retour d'appui : le contrôle s'enfonce légèrement. Sans mouvement si l'utilisateur l'a réduit.
struct PressFeedback: ViewModifier {
    let pressed: Bool
    let scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && !reduceMotion ? scale : 1)
            .animation(reduceMotion ? nil : Motion.press, value: pressed)
    }
}

extension View {
    /// 0,97 pour un bouton ; 0,985 pour une carte, dont le déplacement serait sinon trop ample.
    func pressFeedback(_ pressed: Bool, scale: CGFloat = 0.97) -> some View {
        modifier(PressFeedback(pressed: pressed, scale: scale))
    }
}

/// Accord en français : le singulier vaut pour 0 et 1.
func pl<Count: BinaryInteger>(_ count: Count, _ singular: String, _ plural: String? = nil) -> String {
    count >= 2 ? (plural ?? singular + "s") : singular
}
