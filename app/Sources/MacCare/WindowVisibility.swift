import AppKit
import SwiftUI

/// Signale si la fenêtre de la vue est réellement visible. macOS la considère masquée
/// lorsqu’elle est entièrement recouverte, réduite, sur un autre espace ou écran éteint.
struct WindowVisibilityObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView(onChange: onChange) }
    func updateNSView(_ view: ObserverView, context: Context) { view.onChange = onChange }

    final class ObserverView: NSView {
        var onChange: (Bool) -> Void
        private var lastReported: Bool?

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
            guard let window else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: window)
            // Cet appel peut survenir pendant une mise à jour SwiftUI : l’état change au tour suivant.
            DispatchQueue.main.async { [weak self] in self?.report() }
        }

        @objc private func occlusionChanged() { report() }

        private func report() {
            guard let window else { return }
            let visible = window.occlusionState.contains(.visible)
            guard visible != lastReported else { return }
            lastReported = visible
            onChange(visible)
        }
    }
}

/// Enregistre une vue comme consommatrice des mesures tant qu’elle est affichée et visible.
struct TrayMetricsConsumerModifier: ViewModifier {
    let store: TrayMetricsStore
    let consumer: TrayMetricsStore.Consumer
    @State private var appeared = false
    @State private var windowVisible = true

    func body(content: Content) -> some View {
        content
            .background(WindowVisibilityObserver { visible in
                windowVisible = visible
                sync(appeared: appeared, visible: visible)
            })
            .onAppear { appeared = true; sync(appeared: true, visible: windowVisible) }
            .onDisappear { appeared = false; sync(appeared: false, visible: windowVisible) }
    }

    private func sync(appeared: Bool, visible: Bool) {
        store.setMonitoring(for: consumer, enabled: appeared && visible)
    }
}
