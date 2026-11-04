import AppKit
import SwiftUI

/// Surface commune aux alertes : même flou, pointe et contour, sans prendre le premier plan.
@MainActor
final class MenuBarAlertPresenter {
    private var panel: StorageAlertPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    var isVisible: Bool { panel?.isVisible == true }

    @discardableResult
    func show<Content: View>(_ content: Content, title: String, anchor button: NSStatusBarButton?) -> Bool {
        guard let button, let anchorWindow = button.window, let screen = anchorWindow.screen else { return false }
        dismiss()
        let host = NSHostingView(rootView: content)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let rect = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let originX = min(screen.visibleFrame.maxX - size.width - 8,
                          max(screen.visibleFrame.minX + 8, rect.midX - size.width / 2))
        let panel = StorageAlertPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = title
        panel.setAccessibilityLabel(title)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.onDismiss = { [weak self] in self?.dismiss() }
        panel.install(content: host, bodySize: size, arrowX: rect.midX - originX)
        panel.setFrameOrigin(NSPoint(x: originX, y: anchorWindow.frame.minY - 4 - panel.frame.height))
        self.panel = panel
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let suppress = MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return false }
                if panel.attachedSheet != nil || NSApp.modalWindow != nil { return false }
                if event.type == .keyDown && event.keyCode == 53 { self.dismiss(); return true }
                if event.type != .keyDown, !panel.frame.contains(NSEvent.mouseLocation),
                   (event.window?.level.rawValue ?? 0) < panel.level.rawValue { self.dismiss() }
                return false
            }
            return suppress ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel, !panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.dismiss()
            }
        }
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        return panel.isVisible
    }

    func dismiss() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil; globalMonitor = nil
        panel?.childWindows?.forEach { $0.close() }
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }
}
