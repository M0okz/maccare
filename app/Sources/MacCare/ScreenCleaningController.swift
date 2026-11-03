import AppKit
import SwiftUI

@MainActor
final class ScreenCleaningController: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var secondsRemaining = 0
    private var windows: [NSWindow] = []
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var countdown: Task<Void, Never>?
    private var previousPresentation: NSApplication.PresentationOptions = []
    private weak var previousWindow: NSWindow?
    var timeLabel: String { String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60) }

    func start(seconds: Int = 120) {
        guard !active, !NSScreen.screens.isEmpty else { return }
        secondsRemaining = min(300, max(10, seconds))
        previousWindow = NSApp.keyWindow
        previousPresentation = NSApp.presentationOptions
        active = true
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication]
        for screen in NSScreen.screens {
            let window = ScreenCleaningWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.title = "Mode nettoyage d’écran"
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = NSHostingView(rootView: ScreenCleaningOverlay(controller: self))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
        windows.first?.makeKey()
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
                                           .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
                                           .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, self.active else { return event }
            if event.type == .keyDown && event.keyCode == 53 && event.modifierFlags.contains(.command) {
                self.stop()
            }
            return nil
        }
        // Toute perte de contrôle (veille, changement d'écran, autre app) restaure la présentation.
        for name in [NSApplication.didResignActiveNotification, NSApplication.didChangeScreenParametersNotification,
                     NSApplication.willTerminateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        })
        let deadline = Date().addingTimeInterval(TimeInterval(secondsRemaining))
        countdown = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
                guard let self, active else { return }
                secondsRemaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
                if secondsRemaining == 0 { stop(); return }
            }
        }
    }

    func stop() {
        guard active else { return }
        active = false
        countdown?.cancel(); countdown = nil
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers = []
        NSApp.presentationOptions = previousPresentation
        for window in windows { window.close() }
        windows = []
        previousWindow?.makeKeyAndOrderFront(nil)
    }
}

private final class ScreenCleaningWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct ScreenCleaningOverlay: View {
    @ObservedObject var controller: ScreenCleaningController
    var body: some View {
        VStack(spacing: 0) {
            Text("Appuyez sur ⌘ + Échap pour quitter le mode")
                .font(.body).padding(.top, 70)
            Spacer()
            VStack(spacing: 14) {
                Text(controller.timeLabel).font(.largeTitle.weight(.semibold)).monospacedDigit()
                    .accessibilityLabel("Temps restant").accessibilityValue("\(controller.secondsRemaining) secondes")
                Text("Nettoyez l’écran, le clavier et le trackpad.\nMacCare quittera automatiquement ce mode à la fin du compte à rebours.")
                    .font(.body).multilineTextAlignment(.center)
            }
            Spacer()
        }.padding(.horizontal, 32).frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Color(white: 0.5)).background(Color.black)
            .accessibilityAction(named: Text("Quitter le mode nettoyage d’écran")) { controller.stop() }
    }
}
