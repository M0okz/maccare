import SwiftUI

struct HomeCleaningDistribution: View {
    let breakdown: HomeCleaningBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(breakdown.parts) { part in
                        color(part.kind)
                            .frame(width: geometry.size.width * Double(part.bytes) / Double(max(1, breakdown.total)))
                    }
                }
            }
            .frame(height: 10).clipShape(Capsule()).accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(breakdown.parts) { part in
                        summary(part).fixedSize(horizontal: true, vertical: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(breakdown.parts) { part in
                        HStack(spacing: 10) {
                            Label { Text(part.kind.title) } icon: {
                                Image(systemName: part.kind.symbol).foregroundStyle(color(part.kind)).accessibilityHidden(true)
                            }.foregroundStyle(Theme.muted)
                            Spacer(minLength: 8)
                            Text(humanSize(part.bytes)).fontWeight(.semibold).monospacedDigit()
                        }.font(AppFont.secondary).accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func summary(_ part: HomeCleaningBreakdown.Part) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: part.kind.symbol).font(.title3).foregroundStyle(color(part.kind)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(part.kind.title).font(AppFont.caption).foregroundStyle(Theme.muted)
                Text(humanSize(part.bytes)).font(AppFont.emphasis).monospacedDigit()
            }
        }.accessibilityElement(children: .combine)
    }

    private func color(_ kind: HomeCleaningBreakdown.Kind) -> Color {
        switch kind {
        case .caches: return Color(hex: "#D2B6FF")
        case .temporary: return Color(hex: "#A17BE8")
        case .logs: return Color(hex: "#7C5ABC")
        case .other: return Color(hex: "#BA9BDF")
        }
    }
}
