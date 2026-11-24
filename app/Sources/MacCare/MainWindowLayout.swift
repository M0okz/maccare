import Foundation

struct MainWindowLayout: Equatable {
    let scale: CGFloat
    let minimumContentSize: CGSize

    static let minimumFrameSize = CGSize(width: 1211, height: 773)
    private static let standardWorkspace = CGSize(width: 2400, height: 1400)
    static let standard = MainWindowLayout(visibleScreenSize: standardWorkspace)
    private static let minimumScale: CGFloat = 0.85

    init(visibleScreenSize: CGSize, titleBarHeight: CGFloat = 28) {
        guard visibleScreenSize.width > 0, visibleScreenSize.height > 0,
              visibleScreenSize.width.isFinite, visibleScreenSize.height.isFinite else {
            self = .standard
            return
        }
        // Use the workspace in points, independently of the number of Retina pixels.
        let room = min(visibleScreenSize.width / Self.standardWorkspace.width,
                       visibleScreenSize.height / Self.standardWorkspace.height)
        scale = min(1, max(Self.minimumScale, (room * 20).rounded(.down) / 20))

        let frameHeight = min(Self.minimumFrameSize.height, visibleScreenSize.height)
        minimumContentSize = CGSize(width: min(Self.minimumFrameSize.width, visibleScreenSize.width),
                                    height: max(1, frameHeight - max(0, titleBarHeight)))
    }

    /// Width available to the dashboard after the navigation rail, in native points.
    func dashboardScale(forContentWidth width: CGFloat) -> CGFloat {
        min(scale, max(Self.minimumScale, width / 1200))
    }

    func contentSize(in viewport: CGSize) -> CGSize {
        CGSize(width: viewport.width / scale, height: viewport.height / scale)
    }
}
