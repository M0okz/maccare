import SwiftUI
import AppKit

/// Configure uniquement les fenêtres principales qui hébergent cette vue.
struct WindowConfigurator: NSViewRepresentable {
    @MainActor private static let mainWindows = NSHashTable<NSWindow>.weakObjects()

    static func raiseExistingWindow() -> Bool {
        let window = NSApp.orderedWindows.first { mainWindows.contains($0) && $0.isVisible }
            ?? mainWindows.allObjects.first { $0.isMiniaturized }
        guard let window else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) {}

    final class ObserverView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            mainWindows.add(window)
            // SwiftUI must finish attaching the full-height content before AppKit lays out its titlebar.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window, self?.window === window else { return }
                // SwiftUI conserve la propriété de la barre d’outils.
                window.toolbar?.showsBaselineSeparator = false
                window.toolbar?.allowsUserCustomization = false
                window.toolbar?.displayMode = .iconOnly
                window.toolbarStyle = .unified
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.title = AppBuildIdentity.name
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = false
                window.backgroundColor = NSColor(Color(hex: "#160C2E"))
            }
        }
    }
}
