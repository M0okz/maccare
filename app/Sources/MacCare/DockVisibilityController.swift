import AppKit

/// Les fenêtres de travail gardent le Dock ; le volet de menus reste une présence discrète.
@MainActor
final class DockVisibilityController: NSObject {
    override init() {
        super.init()
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeMainNotification, NSWindow.didBecomeKeyNotification] {
            center.addObserver(self, selector: #selector(windowPresented), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(windowClosing), name: NSWindow.willCloseNotification, object: nil)
        center.addObserver(self, selector: #selector(settingsChanged), name: UserDefaults.didChangeNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    static func policy(menuBarEnabled: Bool, windows: [NSWindow], closing: NSWindow? = nil) -> NSApplication.ActivationPolicy {
        let hasWindow = windows.contains {
            $0 !== closing && $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized)
        }
        return !menuBarEnabled || hasWindow ? .regular : .accessory
    }

    func update(excluding closing: NSWindow? = nil) {
        let policy = Self.policy(menuBarEnabled: MenuBarSetting.enabled, windows: NSApp.windows, closing: closing)
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    static func activateForWindow() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func windowPresented(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.canBecomeMain else { return }
        update()
    }

    @objc private func windowClosing(_ notification: Notification) {
        // willClose est envoyé avant la disparition de la fenêtre dans NSApp.windows.
        let window = notification.object as? NSWindow
        Task { @MainActor [weak self, weak window] in self?.update(excluding: window) }
    }

    @objc private func settingsChanged(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.update() }
    }
}
