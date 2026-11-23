import AppKit

// Visuels originaux, dessinés avec les primitives natives. Aucun asset du produit de référence.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

func bitmap(size: NSSize, scale: Int, draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
        pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let canvas = NSSize(width: 680, height: 460)
func text(_ string: String, top: CGFloat, size: CGFloat, weight: NSFont.Weight, ink: UInt32) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color(ink), .paragraphStyle: style
    ]
    (string as NSString).draw(in: NSRect(x: 24, y: canvas.height - top - size * 1.5,
                                      width: canvas.width - 48, height: size * 1.5), withAttributes: attrs)
}
func background() {
    NSGradient(starting: color(0xFFFFFF), ending: color(0xF6F2FC))!
        .draw(in: NSRect(origin: .zero, size: canvas), angle: -90)
    text("Installez MacCare", top: 48, size: 28, weight: .bold, ink: 0x281546)
    text("Glissez MacCare dans Applications.", top: 94, size: 16, weight: .regular, ink: 0x645775)
    let panel = NSBezierPath(roundedRect: NSRect(x: 58, y: 122, width: 564, height: 182), xRadius: 32, yRadius: 32)
    NSGradient(starting: color(0xEBE0F6), ending: color(0xEEE9FC))!.draw(in: panel, angle: 0)
    // La flèche reste une indication ; les deux icônes sont de vrais éléments du Finder.
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 311, y: 225))
    arrow.line(to: NSPoint(x: 369, y: 225))
    arrow.move(to: NSPoint(x: 356, y: 238))
    arrow.line(to: NSPoint(x: 369, y: 225))
    arrow.line(to: NSPoint(x: 356, y: 212))
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    color(0xB8A7CA).setStroke()
    arrow.stroke()
    text("MacCare", top: 363, size: 24, weight: .bold, ink: 0x6E35CE)
    text("Ouvrez ensuite MacCare depuis Applications.", top: 405, size: 13, weight: .regular, ink: 0x746A82)
}
let normal = bitmap(size: canvas, scale: 1, draw: background)
let retina = bitmap(size: canvas, scale: 2, draw: background)
try normal.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("background-preview.png"))
let image = NSImage(size: canvas)
image.addRepresentation(normal)
image.addRepresentation(retina)
try image.tiffRepresentation!.write(to: output.appendingPathComponent("background.tiff"))
print("Visuels générés : \(output.path)")
