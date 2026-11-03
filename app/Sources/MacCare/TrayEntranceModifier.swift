import SwiftUI

struct TrayEntranceModifier: ViewModifier {
    let index: Int
    let enabled: Bool
    let entered: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(enabled && !entered ? 0 : 1)
            .offset(y: enabled && !entered && !reduceMotion ? 6 : 0)
            .animation(enabled ? .easeOut(duration: reduceMotion ? 0.10 : 0.22).delay(reduceMotion ? 0 : Double(index) * 0.04) : nil, value: entered)
    }
}
