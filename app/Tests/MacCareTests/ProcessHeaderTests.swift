import AppKit
import XCTest
@testable import MacCare

final class ProcessHeaderTests: XCTestCase {
    @MainActor
    func testScrolledContentCannotShowThroughHeaderInEitherAppearance() throws {
        let frame = NSRect(x: 0, y: 0, width: 160, height: 28)
        let table = NSTableView(frame: frame)
        let header = ProcessHeader(frame: frame)
        table.headerView = header
        let column = NSTableColumn(identifier: .init("Nom"))
        column.title = "Nom"
        table.addTableColumn(column)

        func render(over background: NSColor, appearance: NSAppearance) throws -> Data {
            let context = try XCTUnwrap(CGContext(data: nil, width: 160, height: 28,
                bitsPerComponent: 8, bytesPerRow: 640, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            background.setFill()
            frame.fill()
            appearance.performAsCurrentDrawingAppearance { header.draw(frame) }
            return Data(bytes: try XCTUnwrap(context.data), count: context.bytesPerRow * context.height)
        }

        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            XCTAssertEqual(try render(over: .black, appearance: appearance),
                           try render(over: .white, appearance: appearance), name.rawValue)
        }
    }
}
