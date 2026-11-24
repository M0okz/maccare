import AppKit
import SwiftUI
import XCTest
@testable import MacCare

/// Click the rendered checkmark. An AXPress on a Toggle bypasses the mouse hit test.
@MainActor
final class UninstallPointerTests: XCTestCase {
    func testClicksInApplicationsLayoutAtCompactDensity() async throws {
        try await exercise(module: .applicationsOverview, screen: CGSize(width: 1512, height: 945))
    }

    func testClicksAtIntermediateDensity() async throws {
        try await exercise(module: .uninstall, screen: CGSize(width: 2180, height: 1280))
    }

    func testClicksInUninstallLayoutAtStandardDensity() async throws {
        try await exercise(module: .uninstall, screen: CGSize(width: 2400, height: 1400))
    }

    private func exercise(module: Module, screen: CGSize) async throws {
        try XCTSkipIf(NSScreen.main == nil, "A macOS window server is required.")
        let files = FileManager.default
        let name = "MacCarePointer-" + UUID().uuidString
        let identifier = "org.example." + name.lowercased()
        let bundle = files.temporaryDirectory.appendingPathComponent(name + ".app")
        let caches = try XCTUnwrap(files.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let paths = [bundle, caches.appendingPathComponent(name), caches.appendingPathComponent(identifier),
                     caches.appendingPathComponent(identifier + ".plist")]
        try files.createDirectory(at: bundle, withIntermediateDirectories: false)
        defer { for url in paths { try? files.removeItem(at: url) } }
        for (index, url) in paths.dropFirst().enumerated() {
            try Data(repeating: 1, count: 32 + index).write(to: url, options: .withoutOverwriting)
        }

        let model = UninstallModel()
        model.selectedApp = AppInfo(url: bundle, name: name, bundleId: identifier)
        for _ in 0..<200 {
            if !model.isScanning { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(Set(model.residuals.map(\.path)), Set(paths.map { $0.standardizedFileURL.path }))

        let layout = MainWindowLayout(visibleScreenSize: screen)
        let host = NSHostingView(rootView: UninstallView(model: model, layout: layout)
            .modifier(ModulePageLayout(module: module, layout: layout)))
        let size = NSSize(width: 1211, height: 536)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(size)
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(host.bounds.size, size)

        let split = try XCTUnwrap(descendants(host).compactMap { $0 as? NSSplitView }.first)
        let pane = try XCTUnwrap(split.arrangedSubviews.last)
        let visible = host.convert(pane.bounds, from: pane)
        let ids = model.residuals.map(\.id)
        var tested = Set<String>()
        var initialGlyphY = [String: CGFloat]()
        var scrolled = false
        for atBottom in [false, true] {
            if atBottom {
                let scroller = try XCTUnwrap(descendants(pane).compactMap { $0 as? NSScroller }.first)
                scroller.setAccessibilityValue(NSNumber(value: 1.0))
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            // This strip contains the glyphs and excludes the changing summary at the far right.
            let strip = NSRect(x: visible.minX, y: visible.minY + 8, width: 84, height: visible.height - 16)
            model.selection = []
            try await Task.sleep(nanoseconds: 75_000_000)
            let empty = try bitmap(of: host, in: strip)
            var visibleCount = 0
            for id in ids {
                model.selection = [id]
                try await Task.sleep(nanoseconds: 75_000_000)
                let checked = try bitmap(of: host, in: strip)
                model.selection = []
                try await Task.sleep(nanoseconds: 75_000_000)
                guard let point = changedGlyph(empty: empty, checked: checked, in: strip) else { continue }
                if atBottom, let firstY = initialGlyphY[id], abs(point.y - firstY) > 15 { scrolled = true }
                if !atBottom { initialGlyphY[id] = point.y }
                let location = host.convert(point, to: nil)
                try click(location, in: window)
                try await Task.sleep(nanoseconds: 60_000_000)
                XCTAssertEqual(model.selection, [id], "Only the row under the pointer should change.")
                try click(location, in: window)
                try await Task.sleep(nanoseconds: 60_000_000)
                XCTAssertTrue(model.selection.isEmpty, "Clicking the same glyph again should clear the same row.")
                tested.insert(id)
                visibleCount += 1
            }
            XCTAssertGreaterThan(visibleCount, 0)
        }
        XCTAssertTrue(scrolled, "The checkmarks should have moved when the detail scrolled.")
        XCTAssertEqual(tested, Set(ids))
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func bitmap(of view: NSView, in area: NSRect) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: area))
        view.cacheDisplay(in: area, to: bitmap)
        return bitmap
    }

    private func changedGlyph(empty: NSBitmapImageRep, checked: NSBitmapImageRep, in strip: NSRect) -> NSPoint? {
        guard let a = empty.bitmapData, let b = checked.bitmapData else { return nil }
        let stride = empty.bitsPerPixel / 8
        var bounds = CGRect.null
        for y in 0..<empty.pixelsHigh {
            for x in 0..<empty.pixelsWide {
                let offset = y * empty.bytesPerRow + x * stride
                if (0..<stride).contains(where: { abs(Int(a[offset + $0]) - Int(b[offset + $0])) > 32 }) {
                    bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        let sx = strip.width / CGFloat(empty.pixelsWide)
        let sy = strip.height / CGFloat(empty.pixelsHigh)
        guard !bounds.isNull, bounds.width * sx <= 22, bounds.height * sy <= 22,
              bounds.height * sy >= 4, bounds.minY > 0, bounds.maxY < CGFloat(empty.pixelsHigh) else { return nil }
        // Bitmap rows and the flipped hosting view both start at the top.
        return NSPoint(x: strip.minX + bounds.midX * sx, y: strip.minY + bounds.midY * sy)
    }

    private func click(_ point: NSPoint, in window: NSWindow) throws {
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
        }
        // AppKit controls may consume the matching mouse-up in their tracking loop.
        NSApp.postEvent(try event(.leftMouseUp), atStart: true)
        window.sendEvent(try event(.leftMouseDown))
        if let up = NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true) {
            window.sendEvent(up)
        }
    }
}
