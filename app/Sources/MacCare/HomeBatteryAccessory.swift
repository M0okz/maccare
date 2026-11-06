import SwiftUI

struct HomeBatteryAccessory: View {
    let accessory: TrayBatteryTelemetry.Accessory
    var diameter: CGFloat = 40

    var body: some View {
        TrayBatteryGauge(name: accessory.name, symbol: accessory.symbol, percent: accessory.percent,
                         diameter: diameter, lineWidth: 3)
            .help("\(accessory.name) · dernier niveau connu : \(accessory.percent) %")
    }
}
