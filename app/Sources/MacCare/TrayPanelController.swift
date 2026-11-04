import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class TrayPanelController: NSObject {
    private let app: AppState
    private var openMainWindow: () -> Void
    private var openSettings: (() -> Void)?
    private var statusItem: NSStatusItem?
    private var panel: TrayFloatingPanel?
    private var selectedScreen: NSScreen?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var presentationID = UUID()
    private var closing = false
    private lazy var storageAlert: StorageAlertController = StorageAlertController(
        anchor: { [weak self] in self?.statusItem?.button },
        canPresent: { [weak self] in
            guard let self else { return false }
            return self.panel?.isVisible != true && !self.memoryAlert.isVisible && self.app.smartScan.stage != .scanning
                && self.app.smartScan.stage != .cleaning
        },
        openMacCare: { [weak self] in self?.app.show(.smartScan) })
    private lazy var memoryAlert: MemoryAlertController = MemoryAlertController(
        anchor: { [weak self] in self?.statusItem?.button },
        canPresent: { [weak self] in
            guard let self else { return false }
            return self.panel?.isVisible != true && !self.storageAlert.isVisible
                && self.app.smartScan.stage != .scanning && self.app.smartScan.stage != .cleaning
        })

    init(app: AppState, openMainWindow: @escaping () -> Void, openSettings: (() -> Void)?) {
        self.app = app
        self.openMainWindow = openMainWindow
        self.openSettings = openSettings
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.syncVisibility() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.storageAlert.dismiss(); self?.memoryAlert.dismiss(); self?.reposition() }
        })
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.storageAlert.dismiss(); self?.memoryAlert.dismiss(); self?.dismiss(animated: false) }
        })
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            guard pid != ProcessInfo.processInfo.processIdentifier else { return }
            Task { @MainActor in self?.dismiss() }
        })
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss(animated: false)
                self?.storageAlert.suspend()
                self?.memoryAlert.suspend()
                self?.app.trayMetrics.suspend()
            }
        })
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.app.trayMetrics.resume(); self?.storageAlert.resume(); self?.memoryAlert.resume(); self?.syncVisibility() }
        })
        syncVisibility()
    }

    func updateOpenMainWindow(_ action: @escaping () -> Void) { openMainWindow = action }

    private func syncVisibility() {
        defer { storageAlert.syncAvailability(); memoryAlert.syncAvailability() }
        if MenuBarSetting.enabled {
            app.trayMetrics.setMonitoring(for: .menuBar, enabled: true)
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                let icon = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "MacCare")
                icon?.isTemplate = true
                button.image = icon
                button.target = self
                button.action = #selector(toggle)
                button.toolTip = "Afficher le volet MacCare"
                button.setAccessibilityLabel("MacCare")
                button.setAccessibilityHelp("Afficher ou fermer le volet MacCare")
            }
            statusItem = item
        } else {
            app.trayMetrics.setMonitoring(for: .menuBar, enabled: false)
            dismiss(animated: false)
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
        }
    }

    func updateOpenSettings(_ action: @escaping () -> Void) { openSettings = action }

    @objc private func toggle() {
        if panel?.isVisible == true && !closing { dismiss() } else { show() }
    }

    func show() {
        storageAlert.dismiss()
        memoryAlert.dismiss()
        syncVisibility()
        guard statusItem != nil else { return }
        if panel?.isVisible == true && !closing {
            panel?.makeKeyAndOrderFront(nil)
            return
        }
        let id = UUID()
        presentationID = id
        closing = false
        selectedScreen = statusItem?.button?.window?.screen ?? NSScreen.main
        guard let screen = selectedScreen else { return }
        let frame = TrayPanelLayout.frame(in: screen.visibleFrame)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let root = MenuBarView(app: app, smart: app.smartScan, metricsStore: app.trayMetrics,
                               openMainWindowAction: { [weak self] in self?.openMainWindow() },
                               dismissPanel: { [weak self] in self?.dismiss(animated: false) },
                               openSettingsAction: { [weak self] in self?.showSettings() },
                               panelSize: frame.size, animateEntrance: true)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.cornerRadius = TrayPanelLayout.cornerRadius
        host.layer?.masksToBounds = true
        host.layer?.borderWidth = 1
        host.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        panel.contentView = host
        panel.setFrame(frame, display: false)
        panel.alphaValue = 0
        statusItem?.button?.highlight(true)
        installEventMonitors()
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.08 : 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.presentationID == id, !self.closing else { return }
                self.writeQADiagnostics(event: "shown")
            }
        }
        writeQADiagnostics(event: "opening")
    }

    private func showSettings() {
        dismiss(animated: false)
        NSApp.activate(ignoringOtherApps: true)
        if let openSettings { openSettings() }
        else { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
    }

    private func makePanel() -> TrayFloatingPanel {
        let panel = TrayFloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "MacCare — État du Mac"
        panel.setAccessibilityLabel("Volet MacCare")
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .none
        return panel
    }

    func dismiss(animated: Bool = true) {
        guard let panel, panel.isVisible, !closing else { return }
        closing = true
        let id = UUID()
        presentationID = id
        removeEventMonitors()
        statusItem?.button?.highlight(false)
        panel.childWindows?.forEach { $0.close() }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.06 : 0.12
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor in self?.finishDismiss(id: id) }
            }
        } else { finishDismiss(id: id) }
    }

    private func finishDismiss(id: UUID) {
        guard presentationID == id else { return }
        panel?.orderOut(nil)
        // Démonte les vues : annulation des tâches, du test réseau et des popovers.
        panel?.contentView = nil
        closing = false
        writeQADiagnostics(event: "hidden")
    }

    private func reposition() {
        guard let panel, panel.isVisible else { return }
        // Un changement d’écran détruit aussi une ancienne mesure de taille devenue invalide.
        dismiss(animated: false)
    }

    private func installEventMonitors() {
        removeEventMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible else { return event }
                if event.type == .keyDown && event.keyCode == 53 {
                    if self.hasVisibleChild(of: panel) { return event }
                    self.dismiss()
                    return nil
                }
                if event.type != .keyDown && !self.containsMouse(in: panel) && !self.mouseIsOnStatusItem {
                    self.dismiss()
                }
                return event
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel, !self.containsMouse(in: panel), !self.mouseIsOnStatusItem else { return }
                self.dismiss()
            }
        }
    }

    private var mouseIsOnStatusItem: Bool {
        guard let button = statusItem?.button, let window = button.window else { return false }
        let bounds = window.convertToScreen(button.convert(button.bounds, to: nil))
        return bounds.contains(NSEvent.mouseLocation)
    }

    private func containsMouse(in window: NSWindow) -> Bool {
        (window.isVisible && window.frame.contains(NSEvent.mouseLocation)) || (window.childWindows ?? []).contains { containsMouse(in: $0) }
    }

    private func hasVisibleChild(of window: NSWindow) -> Bool {
        (window.childWindows ?? []).contains { $0.isVisible }
    }

    private func removeEventMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    func shutdown() {
        storageAlert.shutdown()
        memoryAlert.shutdown()
        app.trayMetrics.setMonitoring(for: .menuBar, enabled: false)
        dismiss(animated: false)
        removeEventMonitors()
        for token in observers { NotificationCenter.default.removeObserver(token) }
        for token in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        observers = []; workspaceObservers = []
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    private func writeQADiagnostics(event: String) {
        #if DEBUG
        guard let path = Bundle.main.object(forInfoDictionaryKey: "MacCareTrayDiagnostics") as? String,
              let panel, let screen = selectedScreen else { return }
        let record: [String: Any] = ["event": event, "frame": NSStringFromRect(panel.frame),
                                    "visibleFrame": NSStringFromRect(screen.visibleFrame),
                                    "rightInset": screen.visibleFrame.maxX - panel.frame.maxX,
                                    "topInset": screen.visibleFrame.maxY - panel.frame.maxY,
                                    "cornerRadius": TrayPanelLayout.cornerRadius,
                                    "visible": panel.isVisible,
                                    "cpuHistoryCount": app.trayMetrics.snapshot.cpu.points.count,
                                    "cpuHistorySpan": app.trayMetrics.snapshot.cpu.points.last.map { last in last.time - (app.trayMetrics.snapshot.cpu.points.first?.time ?? last.time) } ?? 0,
                                    "metricsMonitoring": app.trayMetrics.isMonitoring,
                                    "reducedMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion]
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        #endif
    }
}
