import Foundation
import Testing
@testable import MacCare

struct MainWindowLayoutTests {
    @Test func dashboardDensityTracksWindowWidthWithoutCompoundingDisplayScale() {
        let roomy = MainWindowLayout.standard
        #expect(roomy.dashboardScale(forContentWidth: 1080) == 0.9)
        #expect(roomy.dashboardScale(forContentWidth: 960) == 0.85)
        #expect(roomy.dashboardScale(forContentWidth: 1360) == 1)
        let compact = MainWindowLayout(visibleScreenSize: CGSize(width: 1920, height: 1080))
        #expect(compact.dashboardScale(forContentWidth: 1080) == compact.scale)
    }

    @Test(arguments: [CGSize(width: 2560, height: 1488), CGSize(width: 1800, height: 1053),
                      // Espaces utilisables simulés de MacBook 13, 14 et 16 pouces.
                      CGSize(width: 1440, height: 820), CGSize(width: 1512, height: 894),
                      CGSize(width: 1728, height: 1030)])
    func windowFrameKeepsTheChosenMinimumAtEveryDisplayScale(screen: CGSize) {
        let layout = MainWindowLayout(visibleScreenSize: screen, titleBarHeight: 28)
        #expect(layout.minimumContentSize == CGSize(width: 1211, height: 745))
        #expect(layout.scale == (screen.width >= 2400 ? 1 : 0.85))
    }

    @Test func actualTitleBarHeightIsIncludedInTheMinimumFrame() {
        let layout = MainWindowLayout(visibleScreenSize: CGSize(width: 2560, height: 1488), titleBarHeight: 40)
        #expect(layout.minimumContentSize == CGSize(width: 1211, height: 733))
    }

    @Test(arguments: [CGSize.zero, CGSize(width: CGFloat.infinity, height: 900)])
    func incompleteDisplayInformationKeepsTheOriginalLayout(screen: CGSize) {
        #expect(MainWindowLayout(visibleScreenSize: screen) == .standard)
    }

    @Test func contentScalingPreservesTheNativeViewport() {
        let layout = MainWindowLayout(visibleScreenSize: CGSize(width: 1800, height: 1000))
        let viewport = layout.minimumContentSize
        let canvas = layout.contentSize(in: viewport)
        #expect(abs(canvas.width * layout.scale - viewport.width) < 0.001)
        #expect(abs(canvas.height * layout.scale - viewport.height) < 0.001)
    }

    @Test func onlyDimensionsThatExceedTheScreenAreCapped() {
        let small = MainWindowLayout(visibleScreenSize: CGSize(width: 900, height: 580))
        #expect(small.minimumContentSize == CGSize(width: 900, height: 552))
        let shallow = MainWindowLayout(visibleScreenSize: CGSize(width: 1280, height: 744))
        #expect(shallow.minimumContentSize == CGSize(width: 1211, height: 716))
        let narrow = MainWindowLayout(visibleScreenSize: CGSize(width: 1000, height: 900))
        #expect(narrow.minimumContentSize == CGSize(width: 1000, height: 745))
    }
}
