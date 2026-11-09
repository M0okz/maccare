import SwiftUI

struct DeviceLowBatteryAlertView: View {
    let device: TrayBatteryTelemetry.Accessory
    let snooze: (Int) -> Void
    let openBattery: () -> Void
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Batterie d’appareil faible")
                    .font(.system(size: titleSize, weight: .bold)).accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Pensez à recharger cet appareil. Ce niveau provient d’un relevé direct récent.")
                    .font(.system(size: bodySize)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Image(systemName: device.symbol).font(.system(size: 28)).accessibilityHidden(true)
                    Text(device.name).font(.system(size: bodySize, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text("\(device.percent) %").font(.system(size: bodySize, weight: .semibold)).foregroundStyle(.orange)
                }.padding(.top, 16).accessibilityElement(children: .combine)
                if let date = device.receivedAt {
                    Text("Relevé reçu à \(date.formatted(.dateTime.hour().minute()))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(24)
            Divider()
            HStack {
                Menu("Ignorer") {
                    Button("Pendant une journée") { snooze(1) }
                    Button("Pendant une semaine") { snooze(7) }
                }.fixedSize()
                Spacer(minLength: 12)
                Button("Ouvrir Batterie", action: openBattery).buttonStyle(StorageAlertPrimaryButtonStyle())
            }.padding(20)
        }.frame(width: 340)
    }
}
