import SwiftUI

/// Le signe de la variation pilote le sens du rouleau natif, comme un altimètre.
struct TrayRollingValue: View {
    let text: String
    let value: Double
    var duration: Double = 0.65
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if #available(macOS 14, *) {
            Text(text).monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText(value: value))
                .animation(reduceMotion ? nil : .easeInOut(duration: duration), value: text)
        } else {
            Text(text).monospacedDigit()
        }
    }
}
