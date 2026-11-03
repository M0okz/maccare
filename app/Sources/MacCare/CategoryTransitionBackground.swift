import SwiftUI

/// Le fond sortant reste présent pendant le fondu, sans retour au fond global violet.
struct CategoryTransitionBackground: View {
    let section: NavigationSection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            CategoryBackground(section: section)
                .id(section)
                .transition(reduceMotion ? .identity : .opacity)
        }
        .background(section.palette.base)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: section)
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
