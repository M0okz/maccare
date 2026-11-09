import SwiftUI

/// Apparence commune aux feuilles secondaires et aux confirmations des gestionnaires.
struct ManagerSheetStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(AppFont.body).foregroundStyle(Theme.fg).background(Theme.surface)
            .environment(\.colorScheme, .light).preferredColorScheme(.light).tint(Theme.accent)
    }
}
