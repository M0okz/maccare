import AppKit
import XCTest
@testable import MacCare

final class DockVisibilityTests: XCTestCase {
    @MainActor func testLastWindowClosingLeavesOnlyMenuBar() {
        let main = window()
        XCTAssertEqual(DockVisibilityController.policy(menuBarEnabled: true, windows: [main]), .regular)
        XCTAssertEqual(DockVisibilityController.policy(menuBarEnabled: true, windows: [main], closing: main), .accessory)
    }

    @MainActor func testTrayAndHiddenWindowsDoNotKeepDockVisible() {
        let hidden = window(visible: false)
        let tray = TrayFloatingPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        XCTAssertEqual(DockVisibilityController.policy(menuBarEnabled: true, windows: [hidden, tray]), .accessory)
    }

    @MainActor func testOtherWorkingWindowKeepsDockVisible() {
        let main = window()
        let other = window()
        XCTAssertEqual(DockVisibilityController.policy(menuBarEnabled: true, windows: [main, other], closing: main), .regular)
    }

    @MainActor func testMinimizedWindowCanStillBeRestoredFromDock() {
        let minimized = window(visible: false, minimized: true)
        XCTAssertEqual(DockVisibilityController.policy(menuBarEnabled: true, windows: [minimized]), .regular)
    }

    @MainActor func testMenuBarDisabledKeepsRegularApplicationPolicy() {
        XCTAssertEqual(DockVisibilityController.policy(menuBarEnabled: false, windows: []), .regular)
    }

    @MainActor private func window(visible: Bool = true, minimized: Bool = false) -> DockTestWindow {
        _ = NSApplication.shared
        let window = DockTestWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.testVisible = visible
        window.testMiniaturized = minimized
        return window
    }
}

@MainActor
private final class DockTestWindow: NSWindow {
    var testVisible = true
    var testMiniaturized = false
    override var isVisible: Bool { testVisible }
    override var isMiniaturized: Bool { testMiniaturized }
    override var canBecomeMain: Bool { true }
}
