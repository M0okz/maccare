import AppKit
import SwiftUI

@MainActor
final class MenuBarAlertPresenter: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    private var escapeMonitor: Any?
    var isVisible: Bool { popover?.isShown == true }

    @discardableResult
    func show<Content: View>(_ content: Content, title: String, anchor button: NSStatusBarButton?) -> Bool {
        guard let button, button.window?.screen != nil else { return false }
        dismiss()

        let host = NSHostingController(rootView: content)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.appearance = NSApp.effectiveAppearance
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        popover.contentViewController = host
        popover.contentSize = host.view.fittingSize
        popover.setAccessibilityLabel(title)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        guard popover.isShown else { return false }
        self.popover = popover
        // Un aperçu ouvert depuis les réglages peut laisser le clavier dans leur fenêtre.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let handled = MainActor.assumeIsolated {
                guard let self, self.isVisible,
                      NSApp.modalWindow == nil, NSApp.keyWindow?.sheetParent == nil,
                      self.popover?.contentViewController?.view.window?.attachedSheet == nil else { return false }
                self.dismiss()
                return true
            }
            return handled ? nil : event
        }
        return true
    }

    func dismiss() {
        let closing = popover
        clearPresentation()
        closing?.close()
    }

    private func clearPresentation() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        popover = nil
    }

    func popoverDidClose(_ notification: Notification) {
        if let closed = notification.object as? NSPopover, closed === popover {
            clearPresentation()
        }
    }
}
