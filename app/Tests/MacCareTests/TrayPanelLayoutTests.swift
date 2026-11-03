import XCTest
@testable import MacCare

final class TrayPanelLayoutTests: XCTestCase {
    func testRightAndTopGapsAreIndependentOfStatusIcon() {
        let screen = CGRect(x: 0, y: 60, width: 1512, height: 898)
        let panel = TrayPanelLayout.frame(in: screen)
        XCTAssertEqual(screen.maxX - panel.maxX, 8)
        XCTAssertEqual(screen.maxY - panel.maxY, 8)
        XCTAssertEqual(panel.width, 540)
        XCTAssertTrue(screen.contains(panel))
    }
    func testSecondaryScreenWithNegativeOrigin() {
        let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1056)
        let panel = TrayPanelLayout.frame(in: screen)
        XCTAssertEqual(panel.maxX, -8)
        XCTAssertEqual(panel.maxY, 848)
        XCTAssertTrue(screen.contains(panel))
    }
    func testShortScreenKeepsPanelInsideUsableArea() {
        let screen = CGRect(x: 200, y: 20, width: 1024, height: 630)
        let panel = TrayPanelLayout.frame(in: screen)
        XCTAssertEqual(panel.height, 614)
        XCTAssertEqual(panel.minY, 28)
        XCTAssertEqual(panel.maxY, 642)
        XCTAssertTrue(screen.contains(panel))
    }
    func testNarrowScreenClampsBothDimensions() {
        let screen = CGRect(x: 500, y: 0, width: 500, height: 600)
        let panel = TrayPanelLayout.frame(in: screen)
        XCTAssertEqual(panel.width, 484)
        XCTAssertEqual(panel.height, 584)
        XCTAssertTrue(screen.contains(panel))
    }
}
