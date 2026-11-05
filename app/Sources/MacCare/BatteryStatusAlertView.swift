import SwiftUI

struct BatteryStatusAlertView: View {
    let completion: BatteryCompletionAlert?
    let limit: Int
    let snooze: (Int) -> Void
    let openBattery: () -> Void
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(completion?.title ?? "Protection de la batterie interrompue")
                    .font(.system(size: titleSize, weight: .bold)).accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                Text(completion == nil
                     ? "MacCare ne peut plus confirmer la protection de la batterie. Ouvrez Batterie pour vérifier l’assistant et la limite de charge."
                     : "L’opération s’est terminée et la protection habituelle est de nouveau active.")
                    .font(.system(size: bodySize)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    Image(systemName: completion == nil ? "battery.100.bolt" : "checkmark.circle.fill")
                        .font(.system(size: 32)).foregroundStyle(completion == nil ? Color.orange : Color.green)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Limite de charge : \(limit) %").font(.system(size: bodySize, weight: .semibold))
                        Text(completion == nil ? "À vérifier" : "Protection rétablie")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(.top, 20).accessibilityElement(children: .combine)
            }.padding(24)
            Divider()
            HStack {
                Menu("Ignorer") {
                    Button("Pendant une journée") { snooze(1) }
                    Button("Pendant une semaine") { snooze(7) }
                }.fixedSize()
                Spacer(minLength: 12)
                Button(completion == nil ? "Vérifier la protection" : "Ouvrir Batterie", action: openBattery)
                    .buttonStyle(StorageAlertPrimaryButtonStyle())
            }.padding(20)
        }.frame(width: 340)
    }
}
