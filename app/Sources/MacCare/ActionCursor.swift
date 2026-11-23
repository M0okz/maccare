import AppKit
import SwiftUI

extension View {
    @ViewBuilder
    func defaultContentCursor() -> some View {
        if #available(macOS 15, *) { pointerStyle(.default) } else { self }
    }

    /// Follows the enabled state of the control, including that of its ancestors.
    func actionCursor() -> some View {
        modifier(ActionCursor())
    }
}

private struct ActionCursor: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(isEnabled ? .link : .default)
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

/// Native panels and Settings toolbar items are drawn outside the SwiftUI button styles.
@MainActor
final class NativeButtonCursor: NSObject {
    func start() {
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willBeginSheetNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(prepare(_:)), name: name, object: nil)
        }
    }

    @objc private func prepare(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        DispatchQueue.main.async {
            let window = window.attachedSheet ?? window
            guard let content = window.contentView else { return }
            if window is NSPanel || window.sheetParent != nil { self.install(in: content) }
            if window.toolbar != nil, let frame = content.superview {
                for item in frame.subviews where item !== content { self.install(in: item) }
            }
        }
    }

    private func install(in view: NSView) {
        if view is NSButton || view.accessibilityRole() == .button {
            guard !view.subviews.contains(where: { $0 is NativeButtonTrackingRegion }) else { return }
            let region = NativeButtonTrackingRegion(frame: view.bounds)
            region.autoresizingMask = [.width, .height]
            region.setAccessibilityElement(false)
            view.addSubview(region)
        } else {
            for child in view.subviews { install(in: child) }
        }
    }
}

private final class NativeButtonTrackingRegion: NSView {
    private var area: NSTrackingArea?
    private var inside = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        self.area = area
    }

    override func mouseEntered(with event: NSEvent) {
        inside = true
        updateCursor()
    }

    override func mouseMoved(with event: NSEvent) { updateCursor() }
    override func cursorUpdate(with event: NSEvent) { updateCursor() }

    private func updateCursor() {
        DispatchQueue.main.async { [weak self] in
            guard let self, inside, let window, window.isKeyWindow, let button = superview,
                  button.isAccessibilityEnabled(),
                  visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) else { return }
            NSCursor.pointingHand.set()
        }
    }

    override func mouseExited(with event: NSEvent) { inside = false }
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
