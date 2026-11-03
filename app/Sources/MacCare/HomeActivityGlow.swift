import SwiftUI

struct HomeActivityGlow: ViewModifier {
    let active: Bool
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .brightness(active ? 0.18 : 0)
            .shadow(color: color.opacity(active ? 0.75 : 0), radius: 8)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: active)
    }
}
