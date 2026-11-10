import SwiftUI

/// Place le rappel dans la barre native commune aux écrans de la fenêtre principale.
struct AppUpdateAvailabilityToolbar: ToolbarContent {
    @ObservedObject var updater: AppUpdater
    var isVisible = true

    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
            item.sharedBackgroundVisibility(.hidden)
        } else {
            item
        }
    }

    private var item: some ToolbarContent {
        // Keep one native item and one owner through launch, onboarding and update cycles.
        ToolbarItem(id: "MacCareUpdateAvailability", placement: .primaryAction) {
            AppUpdateAvailabilityButton(updater: updater)
                .frame(minHeight: 44)
                .opacity(isVisible ? 1 : 0)
                .allowsHitTesting(isVisible)
                .accessibilityHidden(!isVisible)
        }
    }
}
