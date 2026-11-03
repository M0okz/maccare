import SwiftUI

/// Capture l’action de scène avant de créer le NSHostingView indépendant du panneau.
struct TraySceneLifecycle: View {
    let app: AppState
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.frame(width: 0, height: 0).onAppear {
            let action = openWindow
            let open = { action(id: MacCareApp.mainWindowID) }
            app.openMainWindow = open
            AppDelegate.openMainWindow = open
            delegate.configureTray(app: app, openMainWindow: open)
        }
        .background {
            if #available(macOS 14, *) { TraySettingsSceneLifecycle(delegate: delegate) }
        }
    }
}
