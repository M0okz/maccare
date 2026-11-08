import Foundation
import Testing
@testable import MacCare

struct MainWindowLayoutTests {
    @Test func theCurrentMacKeepsItsExistingScaleAndDefaultWindow() {
        let layout = MainWindowLayout(visibleScreenSize: CGSize(width: 2560, height: 1488))
        #expect(layout == .standard)
        #expect(layout.preferredWindowSize == CGSize(width: 1200, height: 720))
    }

    @Test(arguments: [CGSize(width: 1800, height: 1053), CGSize(width: 1728, height: 1029),
                      CGSize(width: 1512, height: 894)])
    func smallerRetinaWorkspacesUseACompactWindowWithTheSameWideLayout(screen: CGSize) {
        let layout = MainWindowLayout(visibleScreenSize: screen)
        #expect(layout.scale == 0.85)
        #expect(layout.preferredWindowSize.width < 1200)
        let canvas = layout.contentSize(in: layout.preferredWindowSize)
        #expect(abs(canvas.width - 1360) < 0.001)
        #expect(abs(canvas.height - 760) < 0.001)
        #expect(canvas.width - 240 - 56 >= 1040)
    }

    @Test(arguments: [CGSize.zero, CGSize(width: CGFloat.infinity, height: 900)])
    func incompleteDisplayInformationKeepsTheOriginalLayout(screen: CGSize) {
        #expect(MainWindowLayout(visibleScreenSize: screen) == .standard)
    }

    @Test func aRestoredOversizedWindowShrinksButASmallManualWindowNeverGrows() {
        let layout = MainWindowLayout(visibleScreenSize: CGSize(width: 1800, height: 1000))
        #expect(layout.reducedRestoredSize(CGSize(width: 1470, height: 790)) == layout.preferredWindowSize)
        let small = CGSize(width: 1000, height: 630)
        #expect(layout.reducedRestoredSize(small) == small)
    }

    @Test func scalingUsesTheFullViewportAndKeepsTheOriginalMinimumCanvas() {
        let layout = MainWindowLayout(visibleScreenSize: CGSize(width: 1800, height: 1000))
        let viewport = CGSize(width: 1156, height: 646)
        let canvas = layout.contentSize(in: viewport)
        #expect(abs(canvas.width * layout.scale - viewport.width) < 0.001)
        #expect(abs(canvas.height * layout.scale - viewport.height) < 0.001)
        let minimum = layout.contentSize(in: layout.minimumWindowSize)
        #expect(abs(minimum.width - 940) < 0.001)
        #expect(abs(minimum.height - 620) < 0.001)
    }
}
