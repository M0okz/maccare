import SwiftUI
import Darwin

struct MacHardwarePresentation: Equatable {
    enum Family: String { case pro13, proNotched, airClassic, airNotched, iMac, mini, studio, tower, laptop, desktop }
    let identifier: String
    let family: Family
    let title: String

    static let current = resolve(identifier: modelIdentifier())

    static func resolve(identifier: String) -> Self {
        // Références reconnues pour le libellé ; le visuel reste fourni par macOS.
        switch identifier {
        case "MacBookPro17,1": return .init(identifier: identifier, family: .pro13, title: "MacBook Pro 13 pouces · M1")
        case "Mac14,7": return .init(identifier: identifier, family: .pro13, title: "MacBook Pro 13 pouces · M2")
        case "MacBookPro18,1", "MacBookPro18,2": return .init(identifier: identifier, family: .proNotched, title: "MacBook Pro 16 pouces")
        case "MacBookPro18,3", "MacBookPro18,4": return .init(identifier: identifier, family: .proNotched, title: "MacBook Pro 14 pouces")
        case "MacBookAir10,1": return .init(identifier: identifier, family: .airClassic, title: "MacBook Air · M1")
        case "Mac14,2", "Mac14,15", "Mac15,12", "Mac15,13": return .init(identifier: identifier, family: .airNotched, title: "MacBook Air")
        case "Macmini9,1", "Mac14,3", "Mac14,12", "Mac16,10", "Mac16,11": return .init(identifier: identifier, family: .mini, title: "Mac mini")
        case "Mac13,1", "Mac13,2", "Mac14,13", "Mac14,14": return .init(identifier: identifier, family: .studio, title: "Mac Studio")
        case "iMac21,1", "iMac21,2": return .init(identifier: identifier, family: .iMac, title: "iMac 24 pouces")
        default:
            if identifier.hasPrefix("MacBookPro") { return .init(identifier: identifier, family: .laptop, title: "MacBook Pro") }
            if identifier.hasPrefix("MacBookAir") { return .init(identifier: identifier, family: .airClassic, title: "MacBook Air") }
            if identifier.hasPrefix("MacBook") { return .init(identifier: identifier, family: .laptop, title: "MacBook") }
            if identifier.hasPrefix("iMac") { return .init(identifier: identifier, family: .iMac, title: "iMac") }
            if identifier.hasPrefix("Macmini") { return .init(identifier: identifier, family: .mini, title: "Mac mini") }
            if identifier.hasPrefix("MacPro") { return .init(identifier: identifier, family: .tower, title: "Mac Pro") }
            if identifier.hasPrefix("MacStudio") { return .init(identifier: identifier, family: .studio, title: "Mac Studio") }
            return .init(identifier: identifier, family: .desktop, title: "Mac")
        }
    }

    private static func modelIdentifier() -> String {
        var length = 0
        guard sysctlbyname("hw.model", nil, &length, nil, 0) == 0, length > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: length)
        guard sysctlbyname("hw.model", &bytes, &length, nil, 0) == 0 else { return "" }
        return String(cString: bytes)
    }
}

/// Visuel matériel fourni par macOS pour le Mac courant, sans reconstruction géométrique.
struct MacHardwareArtwork: View {
    let hardware: MacHardwarePresentation

    var body: some View {
        Image(nsImage: MacHardwareSystemImage.current)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .accessibilityLabel(hardware.title)
    }
}

@MainActor
enum MacHardwareSystemImage {
    /// Visuel d’ordinateur fourni par le système hôte via AppKit.
    /// Le cache conserve une seule image : aucune lecture système à chaque rafraîchissement.
    static let current: NSImage = {
        guard let image = NSImage(named: NSImage.computerName) else {
            return NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: nil) ?? NSImage(size: .init(width: 1, height: 1))
        }
        return trimTransparentPadding(from: image)
    }()

    private static func trimTransparentPadding(from image: NSImage) -> NSImage {
        // Demande la représentation haute résolution à IconServices. Le rectangle de rendu
        // reprend le rapport original ; le recadrage ne modifie aucun pixel du châssis.
        let side = 1024
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                     bytesPerRow: side * 4, space: space,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return image }
        bitmap.clear(CGRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
        let sourceRatio = image.size.width / max(image.size.height, 1)
        let renderSize = sourceRatio >= 1 ? CGSize(width: CGFloat(side), height: CGFloat(side) / sourceRatio) :
                                          CGSize(width: CGFloat(side) * sourceRatio, height: CGFloat(side))
        image.draw(in: NSRect(origin: .zero, size: renderSize), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let pixels = bitmap.data?.assumingMemoryBound(to: UInt8.self), let cgImage = bitmap.makeImage() else { return image }
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side where pixels[y * bitmap.bytesPerRow + x * 4 + 3] > 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }
        let bounds = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cropped = cgImage.cropping(to: bounds) else { return image }
        return NSImage(cgImage: cropped, size: bounds.size)
    }
}
