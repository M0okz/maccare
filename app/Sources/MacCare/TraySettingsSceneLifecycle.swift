import SwiftUI

@available(macOS 14, *)
struct TraySettingsSceneLifecycle: View {
    let delegate: AppDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear.frame(width: 0, height: 0).onAppear {
            let action = openSettings
            delegate.configureOpenSettings { action() }
        }
    }
}
