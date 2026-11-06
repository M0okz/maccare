import AppKit

/// Géométrie dans le repère du moniteur choisi, y compris ses origines négatives.
enum TrayPanelLayout {
    static let inset: CGFloat = 8
    static let width: CGFloat = 420
    static let footerHeight: CGFloat = 44
    static let maximumBodyHeight: CGFloat = 546
    static let cornerRadius: CGFloat = 16

    static func frame(in visibleFrame: CGRect) -> CGRect {
        let width = min(Self.width, max(0, visibleFrame.width - 2 * inset))
        let height = min(maximumBodyHeight + footerHeight, max(0, visibleFrame.height - 2 * inset))
        return CGRect(x: visibleFrame.maxX - inset - width,
                      y: visibleFrame.maxY - inset - height, width: width, height: height)
    }
}
