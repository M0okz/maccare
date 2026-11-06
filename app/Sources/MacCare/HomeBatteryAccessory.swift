import SwiftUI

struct HomeBatteryAccessory: View {
    let accessory: TrayBatteryTelemetry.Accessory
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 50

    var body: some View {
        VStack(spacing: 5) {
            TrayBatteryGauge(name: accessory.name, symbol: accessory.symbol, percent: accessory.percent,
                             diameter: diameter, lineWidth: 4)
                .accessibilityHidden(true)
            Text(accessory.name).font(AppFont.caption).foregroundStyle(Theme.muted)
                .lineLimit(2).multilineTextAlignment(.center).help(accessory.name)
            Text("\(accessory.percent) %").font(AppFont.emphasis).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessory.name)
        .accessibilityValue("\(accessory.percent) %")
    }
}
