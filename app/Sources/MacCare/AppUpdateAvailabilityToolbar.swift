import SwiftUI

/// Place le rappel dans la barre native commune aux écrans de la fenêtre principale.
struct AppUpdateAvailabilityToolbar: ToolbarContent {
    @ObservedObject var updater: AppUpdater
    var isVisible = true

    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            item.sharedBackgroundVisibility(.hidden)
        } else {
            item
        }
    }

    private var item: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            if isVisible, updater.availableVersion != nil {
                Spacer()
                AppUpdateAvailabilityButton(updater: updater)
            }
        }
    }
}
