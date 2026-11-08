import Foundation

struct MainWindowLayout: Equatable {
    let scale: CGFloat

    static let standard = MainWindowLayout(scale: 1)
    static let minimumContentSize = CGSize(width: 940, height: 620)
    static let compactWindowMigrationKey = "mainWindowCompactDisplayLayoutApplied"

    init(visibleScreenSize: CGSize) {
        guard visibleScreenSize.width > 0, visibleScreenSize.height > 0,
              visibleScreenSize.width.isFinite, visibleScreenSize.height.isFinite else {
            self = .standard
            return
        }
        // Use the workspace in points, independently of the number of Retina pixels.
        let room = min(visibleScreenSize.width / 2400, visibleScreenSize.height / 1400)
        scale = min(1, max(0.85, (room * 20).rounded(.down) / 20))
    }

    private init(scale: CGFloat) { self.scale = scale }

    var isCompact: Bool { scale < 1 }
    var minimumWindowSize: CGSize {
        CGSize(width: Self.minimumContentSize.width * scale, height: Self.minimumContentSize.height * scale)
    }
    var preferredWindowSize: CGSize {
        guard isCompact else { return CGSize(width: 1200, height: 720) }
        return CGSize(width: 1360 * scale, height: 760 * scale)
    }
    func contentSize(in viewport: CGSize) -> CGSize {
        CGSize(width: viewport.width / scale, height: viewport.height / scale)
    }
    func reducedRestoredSize(_ current: CGSize) -> CGSize {
        CGSize(width: min(current.width, preferredWindowSize.width),
               height: min(current.height, preferredWindowSize.height))
    }
}
