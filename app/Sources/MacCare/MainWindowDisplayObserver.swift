import AppKit
import SwiftUI

struct MainWindowDisplayObserver: NSViewRepresentable {
    let onChange: (MainWindowLayout) -> Void

    static func layout(for window: NSWindow) -> MainWindowLayout {
        guard let screen = window.screen else { return .standard }
        let titleBar = max(0, window.frame.height - window.contentLayoutRect.height)
        if AppBuildIdentity.isDevelopment && ProcessInfo.processInfo.arguments.contains("--preview-compact-display") {
            return MainWindowLayout(visibleScreenSize: CGSize(width: 1800, height: 1000), titleBarHeight: titleBar)
        }
        return MainWindowLayout(visibleScreenSize: screen.visibleFrame.size, titleBarHeight: titleBar)
    }

    func makeNSView(context: Context) -> ObserverView { ObserverView(onChange: onChange) }
    func updateNSView(_ view: ObserverView, context: Context) { view.onChange = onChange }

    final class ObserverView: NSView {
        var onChange: (MainWindowLayout) -> Void
        private var lastLayout: MainWindowLayout?

        init(onChange: @escaping (MainWindowLayout) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            for name in [NSWindow.didChangeScreenNotification, NSWindow.didChangeBackingPropertiesNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: name, object: window)
            }
            NotificationCenter.default.addObserver(self, selector: #selector(displayChanged),
                                                   name: NSApplication.didChangeScreenParametersNotification, object: nil)
            reportOnNextTurn()
        }

        @objc private func displayChanged() { reportOnNextTurn() }

        private func reportOnNextTurn() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window, window.screen != nil else { return }
                let layout = MainWindowDisplayObserver.layout(for: window)
                guard layout != lastLayout else { return }
                lastLayout = layout
                onChange(layout)
            }
        }
    }
}
