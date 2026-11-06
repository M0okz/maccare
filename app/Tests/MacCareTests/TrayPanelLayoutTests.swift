import XCTest
@testable import MacCare

final class TrayPanelLayoutTests: XCTestCase {
    func testRightAndTopGapsAreIndependentOfStatusIcon() {
        let screen = CGRect(x: 0, y: 60, width: 1512, height: 898)
        let panel = TrayPanelLayout.frame(in: screen)
        XCTAssertEqual(screen.maxX - panel.maxX, 8)
        XCTAssertEqual(screen.maxY - panel.maxY, 8)
        XCTAssertEqual(panel.width, 420)
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
        let screen = CGRect(x: 200, y: 20, width: 1024, height: 400)
        let panel = TrayPanelLayout.frame(in: screen)
        XCTAssertEqual(panel.height, 384)
        XCTAssertEqual(panel.minY, 28)
        XCTAssertEqual(panel.maxY, 412)
        XCTAssertTrue(screen.contains(panel))
    }
    func testNarrowScreenClampsBothDimensions() {
        let screen = CGRect(x: 500, y: 0, width: 400, height: 400)
        let panel = TrayPanelLayout.frame(in: screen)
        XCTAssertEqual(panel.width, 384)
        XCTAssertEqual(panel.height, 384)
        XCTAssertTrue(screen.contains(panel))
    }
}
