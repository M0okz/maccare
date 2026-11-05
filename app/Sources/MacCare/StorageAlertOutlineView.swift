import AppKit

/// Un trait unique au-dessus du matériau ; laisse les clics atteindre les boutons.
final class StorageAlertOutlineView: NSView {
    private let path: CGPath

    init(frame: NSRect, path: CGPath) {
        var inset = CGAffineTransform(a: (frame.width - 1) / frame.width, b: 0,
                                     c: 0, d: (frame.height - 1) / frame.height,
                                     tx: 0.5, ty: 0.5)
        self.path = path.copy(using: &inset) ?? path
        super.init(frame: frame)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.addPath(path)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.65).cgColor)
        context.setLineWidth(1)
        context.strokePath()
    }
}
