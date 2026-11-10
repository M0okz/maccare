import SwiftUI
import AppKit

/// Rend la barre de titre transparente : le dégradé violet monte jusqu'en haut (plus de bandeau gris).
struct WindowConfigurator: NSViewRepresentable {
    private static let sizeMigrationKey = "mainWindowSize1200x720Applied"

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { apply(to: nsView) }

    /// Ne configure que la fenêtre qui héberge cette vue, jamais les dialogues ou le panneau de menu.
    private func apply(to view: NSView, attempt: Int = 0) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                if attempt < 30 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        apply(to: view, attempt: attempt + 1)
                    }
                }
                return
            }
            // SwiftUI owns the toolbar for this window. Assigning window.toolbar here
            // races its observer lifecycle when the update notice changes visibility.
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
            // Aligne aussi une fenêtre restaurée de l'ancienne version, une seule fois.
            // Les redimensionnements manuels suivants restent mémorisés par macOS.
            let layout = window.screen.map { MainWindowDisplayObserver.layout(on: $0) } ?? .standard
            if !UserDefaults.standard.bool(forKey: Self.sizeMigrationKey) {
                window.setContentSize(layout.preferredWindowSize)
                window.center()
                UserDefaults.standard.set(true, forKey: Self.sizeMigrationKey)
            }
            if layout.isCompact && !UserDefaults.standard.bool(forKey: MainWindowLayout.compactWindowMigrationKey),
               !window.styleMask.contains(.fullScreen), !window.isMiniaturized {
                let current = window.contentView?.frame.size ?? window.frame.size
                let reduced = layout.reducedRestoredSize(current)
                if reduced.width < current.width || reduced.height < current.height {
                    window.setContentSize(reduced)
                    window.center()
                }
                UserDefaults.standard.set(true, forKey: MainWindowLayout.compactWindowMigrationKey)
            }
        }
    }
}

