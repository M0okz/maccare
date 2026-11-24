import AppKit
import XCTest
@testable import MacCare

final class ProcessHeaderTests: XCTestCase {
    @MainActor
    func testLoadMarkerAndApplicationIconKeepTheirPlaceAtEveryCPULevel() throws {
        let loads: [Double?] = [nil, 7, 65, 90]
        let processes = loads.enumerated().map { index, load in
            TrayProcess(id: .init(pid: pid_t(100_000 + index), startedSeconds: 1, startedMicroseconds: 0),
                        name: "Test", userID: getuid(), memory: 0, cpuPercent: load, executable: "")
        }
        let rows = HomeProcessGroup.collect(processes)
        let list = HomeProcessList(rows: rows, processCount: rows.count, cpuSummary: "",
                                   controller: TrayProcessController(), isCardHovered: false,
                                   sort: .constant(HomeProcessSort()), query: .constant("")) { _ in }
        let coordinator = list.makeCoordinator()
        let table = NSTableView()
        let column = NSTableColumn(identifier: .init(HomeProcessColumn.name.rawValue))
        for (index, row) in rows.enumerated() {
            let cell = try XCTUnwrap(coordinator.tableView(table, viewFor: column, row: index) as? NSTableCellView)
            cell.frame = NSRect(x: 0, y: 0, width: 360, height: 30)
            cell.layoutSubtreeIfNeeded()
            let marker = try XCTUnwrap(cell.subviews.compactMap { $0 as? NSBox }.first)
            let icon = try XCTUnwrap(cell.imageView)
            let label = try XCTUnwrap(cell.textField)
            XCTAssertEqual(marker.frame.minX, 12)
            XCTAssertEqual(marker.frame.size, NSSize(width: 3, height: 15))
            XCTAssertEqual(icon.frame.minX - marker.frame.maxX, 9)
            let textLeading = label.alignmentRect(forFrame: label.frame).minX
            XCTAssertEqual(textLeading - icon.alignmentRect(forFrame: icon.frame).maxX, 8)
            if let accent = row.cpuLevel.accent {
                XCTAssertEqual(marker.fillColor, accent)
            } else {
                XCTAssertEqual(marker.fillColor.alphaComponent, 0.13, accuracy: 0.002)
            }
        }
    }

    @MainActor
    func testTransparentHeaderShowsCardAndStaysOutsideScrollingRows() throws {
        let container = ProcessListContainer(frame: NSRect(x: 0, y: 0, width: 500, height: 180))
        let scroll = container.scroll
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 500, height: 1200))
        let header = ProcessHeader(frame: NSRect(x: 0, y: 0, width: 500, height: ProcessHeader.height))
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
            XCTAssertEqual(titles.height, 25)
            XCTAssertEqual(scroll.contentView.frame.minY, titles.maxY)
            XCTAssertGreaterThan(scroll.contentView.frame.height, 0)
        }

        let ctx = try XCTUnwrap(CGContext(data: nil, width: 500, height: Int(header.bounds.height), bitsPerComponent: 8,
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
