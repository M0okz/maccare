import AppKit
import XCTest
@testable import MacCare

final class ProcessHeaderTests: XCTestCase {
    @MainActor
    func testTransparentHeaderShowsCardAndStaysOutsideScrollingRows() throws {
        let container = ProcessListContainer(frame: NSRect(x: 0, y: 0, width: 500, height: 180))
        let scroll = container.scroll
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 500, height: 1200))
        let header = ProcessHeader(frame: NSRect(x: 0, y: 0, width: 500, height: 24))
        let column = NSTableColumn(identifier: .init("Nom"))
        column.title = "Nom"
        table.style = .plain
        table.headerView = header
        table.addTableColumn(column)
        scroll.documentView = table
        scroll.tile()

        XCTAssertFalse(header.isOpaque)
        XCTAssertEqual(scroll.contentView.contentInsets.top, 0)
        for offset in [0, 250, 50] {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
            let titles = scroll.convert(header.bounds, from: header)
            XCTAssertEqual(titles.height, 24)
            XCTAssertEqual(scroll.contentView.frame.minY, titles.maxY)
            XCTAssertGreaterThan(scroll.contentView.frame.height, 0)
        }

        let ctx = try XCTUnwrap(CGContext(data: nil, width: 500, height: 24, bitsPerComponent: 8,
            bytesPerRow: 2000, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            ctx.clear(header.bounds)
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance { header.draw(header.bounds) }
            let bytes = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
            XCTAssertEqual(bytes[12 * ctx.bytesPerRow + 350 * 4 + 3], 0)
        }
    }
}
