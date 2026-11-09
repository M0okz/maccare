import SwiftUI

struct ApplicationsInsightCard: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let information: ApplicationCardInformation
    let actionTitle: String
    let action: () -> Void
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(title).font(.system(size: titleSize, weight: .semibold))
                        .accessibilityAddTraits(.isHeader).fixedSize(horizontal: false, vertical: true)
                    ApplicationCardInfoButton(information: information, arrowEdge: information == .unused ? .bottom : .top, onDetails: action)
                }
                Spacer(minLength: 0)
                Image(systemName: symbol).font(.system(size: 28, weight: .medium))
                    .foregroundStyle(tint.shade(0.3)).accessibilityHidden(true)
            }
            Text(detail).font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack { Spacer(); Button(actionTitle, action: action).buttonStyle(SecondaryActionButtonStyle()) }
        }
        .padding(20).frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.065))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.1))))
    }
}
