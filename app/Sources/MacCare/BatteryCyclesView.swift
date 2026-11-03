import SwiftUI
import MacCareBattery

struct BatteryCyclesView: View {
    @ObservedObject var model: BatteryModel
    @State private var confirmingCalibration = false
    private var canStart: Bool {
        model.active && model.protection?.ownedByCaller == true && model.supportsDischarge &&
        model.snapshot?.onAC == true && !model.controlsBusy && model.cycle == nil
    }
    var body: some View {
        GroupBox("Cycles de batterie") {
            VStack(alignment: .leading, spacing: 20) {
                if let cycle = model.cycle {
                    Label(cycle.message, systemImage: "arrow.triangle.2.circlepath").font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("La progression dépend de votre utilisation. Le Mac et son chargeur doivent rester disponibles jusqu’à la fin du cycle.")
                    Button("Annuler le cycle et rétablir l’alimentation") { Task { await model.perform(.cancelCycle) } }
                        .disabled(model.controlsBusy || model.protection?.ownedByCaller != true)
                } else {
                    Text("Décharger jusqu’à la limite").font(.headline)
                    Text("Le Mac utilise sa batterie tout en restant branché, puis reprend l’alimentation secteur à \(model.configuration.limit) %. Cette action est volontaire et peut être annulée.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Décharger vers \(model.configuration.limit) %") { Task { await model.perform(.discharge) } }
                        .disabled(!canStart || (model.snapshot?.percent ?? 0) <= model.configuration.limit)
                    Divider()
                    Text("Étalonnage du niveau de batterie").font(.headline)
                    Text("Le cycle recharge à 100 %, décharge vers 10 %, recharge à nouveau à 100 %, puis revient à votre limite. Il aide à réévaluer le niveau de charge ; il ne répare pas une batterie usée. Il peut durer plusieurs heures.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Démarrer l’étalonnage…") { confirmingCalibration = true }.disabled(!canStart)
                }
                if !model.supportsDischarge {
                    Label("Le contrôle de l’adaptateur n’est pas disponible avec le contrôleur actuellement détecté.", systemImage: "info.circle")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else if !model.active {
                    Text("Activez d’abord la protection dans l’onglet Réglages.").foregroundStyle(.secondary)
                }
                Text("La veille, la fermeture de MacCare ou une mesure devenue inconnue interrompent le cycle et déclenchent la restauration de l’alimentation.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(12)
        }
        .confirmationDialog("Démarrer le cycle complet d’étalonnage ?", isPresented: $confirmingCalibration, titleVisibility: .visible) {
            Button("Démarrer le cycle complet") { Task { await model.perform(.calibrate) } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Laissez le chargeur branché. La batterie descendra volontairement vers 10 % pendant ce cycle long. Vous pourrez annuler à tout moment ; votre limite de \(model.configuration.limit) % sera rétablie à la fin.")
        }
    }
}
