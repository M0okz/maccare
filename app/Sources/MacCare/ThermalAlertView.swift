import SwiftUI

struct ThermalAlertView: View {
    let state: ProcessInfo.ThermalState
    let snooze: (Int) -> Void
    let openActivity: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Label(AdditionalAlertKind.thermal.title, systemImage: "thermometer.high")
                    .font(.headline).accessibilityAddTraits(.isHeader)
                Text(state == .critical
                     ? "macOS a signalé un état thermique critique. Mettez en pause les tâches les plus exigeantes pour laisser le Mac refroidir."
                     : "Le Mac chauffe depuis une minute. Consultez les processus actifs pour identifier les tâches les plus exigeantes.")
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(24)
            Divider()
            HStack {
                Menu("Ignorer") {
                    Button("Pendant une journée") { snooze(1) }
                    Button("Pendant une semaine") { snooze(7) }
                }.fixedSize()
                Spacer(minLength: 12)
                Button("Voir les processus", action: openActivity)
                    .buttonStyle(StorageAlertPrimaryButtonStyle())
            }.padding(20)
        }.frame(width: 340)
    }
}
