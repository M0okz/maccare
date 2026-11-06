import SwiftUI

struct TrayDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).foregroundStyle(TrayAppearance.secondary)
            Spacer(minLength: 0)
            Text(value).fontWeight(.semibold).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
