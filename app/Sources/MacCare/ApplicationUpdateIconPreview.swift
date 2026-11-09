import SwiftUI
import AppKit

/// A compact Dock-like cluster of real apps; the full names remain in the updates list.
struct ApplicationUpdateIconPreview: View {
    let urls: [URL]
    let totalCount: Int
    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 72

    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .center, spacing: -14) {
                ForEach(Array(urls.prefix(3).enumerated()), id: \.element) { index, url in
                    let prominent = urls.count == 1 || index == 1
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(width: prominent ? iconSize : iconSize * 0.83,
                               height: prominent ? iconSize : iconSize * 0.83)
                        .shadow(color: .black.opacity(0.16), radius: 5, y: 4)
                        .rotationEffect(.degrees(urls.count > 1 ? (index == 0 ? -8 : index == 2 ? 8 : 0) : 0))
                        .offset(y: prominent ? -4 : 5)
                        .mask {
                            if index == 2 {
                                LinearGradient(stops: [.init(color: .white, location: 0.35),
                                                       .init(color: .clear, location: 0.82)],
                                               startPoint: .leading, endPoint: .trailing)
                            } else { Rectangle() }
                        }
                        .zIndex(prominent ? 1 : 0)
                }
            }
            if totalCount > urls.count {
                Text("+\(totalCount - urls.count)")
                    .font(AppFont.secondary.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
        }
        .frame(maxWidth: .infinity, minHeight: iconSize + 8, alignment: .leading)
        .accessibilityHidden(true)
    }
}
