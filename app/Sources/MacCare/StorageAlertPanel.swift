import AppKit

/// Une seule surface de flou, découpée avec sa pointe : aucun contour de verre superposé.
final class StorageAlertPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }

    func install(content: NSView, bodySize: NSSize, arrowX: CGFloat) {
        let arrowHeight: CGFloat = 10
        let bounds = CGRect(origin: .zero, size: NSSize(width: bodySize.width, height: bodySize.height + arrowHeight))
        let body = CGRect(origin: .zero, size: bodySize)
        let radius: CGFloat = 20
        let x = min(body.maxX - radius - 12, max(radius + 12, arrowX))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: body.maxX - radius, y: 0))
        path.addQuadCurve(to: CGPoint(x: body.maxX, y: radius), control: CGPoint(x: body.maxX, y: 0))
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: body.maxX - radius, y: body.maxY), control: CGPoint(x: body.maxX, y: body.maxY))
        path.addLine(to: CGPoint(x: x + 12, y: body.maxY))
        path.addCurve(to: CGPoint(x: x + 4, y: body.maxY + 7), control1: CGPoint(x: x + 8, y: body.maxY), control2: CGPoint(x: x + 6, y: body.maxY + 5))
        path.addQuadCurve(to: CGPoint(x: x - 4, y: body.maxY + 7), control: CGPoint(x: x, y: body.maxY + 13))
        path.addCurve(to: CGPoint(x: x - 12, y: body.maxY), control1: CGPoint(x: x - 6, y: body.maxY + 5), control2: CGPoint(x: x - 8, y: body.maxY))
        path.addLine(to: CGPoint(x: radius, y: body.maxY))
        path.addQuadCurve(to: CGPoint(x: 0, y: body.maxY - radius), control: CGPoint(x: 0, y: body.maxY))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: .zero)
        path.closeSubpath()

        let root = NSView(frame: bounds)
        root.wantsLayer = true
        let material = NSVisualEffectView(frame: bounds)
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        // NSVisualEffectView masque aussi le flou, au lieu de peindre une fausse transparence.
        material.maskImage = NSImage(size: bounds.size, flipped: false) { _ in
            NSColor.white.setFill()
            NSGraphicsContext.current?.cgContext.addPath(path)
            NSGraphicsContext.current?.cgContext.fillPath()
            return true
        }
        root.addSubview(material)
        content.frame = body
        material.addSubview(content)

        root.addSubview(StorageAlertOutlineView(frame: bounds, path: path))
        contentView = root
        setContentSize(bounds.size)
    }
}
