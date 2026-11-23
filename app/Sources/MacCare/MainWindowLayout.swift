import Foundation

struct MainWindowLayout: Equatable {
    let scale: CGFloat
    let minimumWindowSize: CGSize
    let preferredWindowSize: CGSize

    static let standard = MainWindowLayout(scale: 1)
    private static let minimumScale: CGFloat = 0.85
    static let minimumContentSize = CGSize(width: 1120, height: 700)
    static let compactWindowMigrationKey = "mainWindowCompactDisplayLayoutApplied"

    init(visibleScreenSize: CGSize, titleBarHeight: CGFloat = 0) {
        guard visibleScreenSize.width > 0, visibleScreenSize.height > 0,
              visibleScreenSize.width.isFinite, visibleScreenSize.height.isFinite else {
            self = .standard
            return
        }
        // Use the workspace in points, independently of the number of Retina pixels.
        let room = min(visibleScreenSize.width / 2400, visibleScreenSize.height / 1400)
        let scale = min(1, max(Self.minimumScale, (room * 20).rounded(.down) / 20))
        let available = CGSize(width: visibleScreenSize.width,
                               height: max(1, visibleScreenSize.height - max(0, titleBarHeight)))
        self.init(scale: scale, available: available)
    }

    private init(scale: CGFloat, available: CGSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                           height: CGFloat.greatestFiniteMagnitude)) {
        self.scale = scale
        let base = Self.minimumContentSize
        minimumWindowSize = CGSize(width: min(base.width * scale, available.width),
                                   height: min(base.height * scale, available.height))
        let preferred = scale < 1 ? CGSize(width: 1360 * scale, height: 760 * scale) : CGSize(width: 1200, height: 720)
        preferredWindowSize = CGSize(width: min(preferred.width, available.width),
                                     height: min(preferred.height, available.height))
    }

    var isCompact: Bool { scale < 1 }

    /// Width available to the dashboard after the navigation rail, in native points.
    func dashboardScale(forContentWidth width: CGFloat) -> CGFloat {
        min(scale, max(Self.minimumScale, width / 1200))
    }

    func contentSize(in viewport: CGSize) -> CGSize {
        CGSize(width: viewport.width / scale, height: viewport.height / scale)
    }
    func reducedRestoredSize(_ current: CGSize) -> CGSize {
        CGSize(width: max(minimumWindowSize.width, min(current.width, preferredWindowSize.width)),
               height: max(minimumWindowSize.height, min(current.height, preferredWindowSize.height)))
    }
}
