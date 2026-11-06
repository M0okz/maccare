import SwiftUI

/// Une seule échelle de lecture pour les mesures de la vue d’ensemble.
struct TrayMetricTile<Details: View, Indicator: View>: View {
    let title: String
    let symbol: String
    let value: String
    @ViewBuilder let details: () -> Details
    @ViewBuilder let indicator: () -> Indicator
    @ScaledMetric(relativeTo: .title3) private var valueSize = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium)).lineLimit(1)
            HStack(spacing: 8) {
                Text(value)
                    .font(.system(size: valueSize, weight: .semibold))
                    .monospacedDigit().lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                indicator()
            }
            details()
                .font(.caption2).foregroundStyle(TrayAppearance.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .padding(8)
    }
}
