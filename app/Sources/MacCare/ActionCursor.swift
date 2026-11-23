import AppKit
import SwiftUI

extension View {
    /// Follows the enabled state of the control, including that of its ancestors.
    func actionCursor() -> some View {
        modifier(ActionCursor())
    }
}

private struct ActionCursor: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(isEnabled ? .link : nil)
        } else {
            content.background {
                if isEnabled { LegacyCursorRegion().accessibilityHidden(true) }
            }
        }
    }
}

private struct LegacyCursorRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> HandCursorRegion { HandCursorRegion() }
    func updateNSView(_ nsView: HandCursorRegion, context: Context) {}
}

private final class HandCursorRegion: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(visibleRect, cursor: .pointingHand)
    }
}

/// AppKit draws alert buttons and the Settings toolbar outside our SwiftUI styles.
/// Only inspect the local event's system control. AppKit handles clicks and tracking normally.
@MainActor
final class NativeButtonCursor: NSObject {
    private var monitor: Any?
    private var previousCursor: NSCursor?
    private var updateScheduled = false

    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey(_:)),
                                               name: NSWindow.didResignKeyNotification, object: nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate, .leftMouseDown]) { [weak self] event in
            self?.track(event)
            return event
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    @objc private func windowResignedKey(_ notification: Notification) { restoreCursor() }

    private func restoreCursor() {
        if let previousCursor, NSCursor.current == .pointingHand { previousCursor.set() }
        previousCursor = nil
    }

    private func track(_ event: NSEvent) {
        guard let window = NSApp.keyWindow, event.type != .leftMouseDown else { restoreCursor(); return }
        let inToolbar = window.toolbar != nil && window.mouseLocationOutsideOfEventStream.y >= window.contentLayoutRect.maxY
        guard inToolbar || window is NSPanel || window.sheetParent != nil else { restoreCursor(); return }
        guard !updateScheduled else { return }
        updateScheduled = true

        // AppKit finishes dispatching all tracking events before we choose the cursor for the final position.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            updateScheduled = false
            let point = NSEvent.mouseLocation
            guard let window = NSApp.keyWindow, window.frame.contains(point),
                  NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0) == window.windowNumber,
                  let target = window.accessibilityHitTest(point) as? NSAccessibilityProtocol else { restoreCursor(); return }
            let inToolbar = window.toolbar != nil && window.convertPoint(fromScreen: point).y >= window.contentLayoutRect.maxY
            guard Self.isNativeButton(target, inToolbar: inToolbar) else { restoreCursor(); return }
            if previousCursor == nil { previousCursor = NSCursor.current == .pointingHand ? .arrow : NSCursor.current }
            NSCursor.pointingHand.set()
        }
    }

    private static func isNativeButton(_ element: NSAccessibilityProtocol, inToolbar: Bool) -> Bool {
        switch element.accessibilityRole() {
        case .button, .radioButton, .checkBox, .popUpButton:
            return element.isAccessibilityEnabled() && (inToolbar || element is NSCell || element is NSControl)
        case .image, .staticText:
            guard let parent = element.accessibilityParent() as? NSAccessibilityProtocol else { return false }
            return isNativeButton(parent, inToolbar: inToolbar)
        default:
            return false
        }
    }
}

struct PlainActionButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration).buttonStyle(.plain).actionCursor()
    }
}

extension PrimitiveButtonStyle where Self == PlainActionButtonStyle {
    static var plainAction: Self { Self() }
}

final class ActionPopUpButton: NSPopUpButton {
    override var isEnabled: Bool {
        didSet {
            if oldValue != isEnabled { window?.invalidateCursorRects(for: self) }
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled { addCursorRect(visibleRect, cursor: .pointingHand) }
    }
}
