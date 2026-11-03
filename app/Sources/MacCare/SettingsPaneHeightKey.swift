import SwiftUI

/// Each pane reports its natural height so the native settings window follows its content.
struct SettingsPaneHeightKey: PreferenceKey {
    static var defaultValue: [SettingsTab: CGFloat] = [:]

    static func reduce(value: inout [SettingsTab: CGFloat], nextValue: () -> [SettingsTab: CGFloat]) {
        value.merge(nextValue()) { _, measured in measured }
    }
}
