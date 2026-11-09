import SwiftUI
import MacCareBattery

struct BatteryDischargeView: View {
    @ObservedObject var model: BatteryModel
    private var canStart: Bool {
        model.active && model.protection?.ownedByCaller == true && model.supportsDischarge &&
        model.snapshot?.onAC == true && !model.controlsBusy && model.cycle == nil
    }
    var body: some View {
        GroupBox("Décharger jusqu’à la limite") {
            VStack(alignment: .leading, spacing: 14) {
                if let cycle = model.cycle {
                    Label(cycle.message, systemImage: "arrow.triangle.2.circlepath").font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("La durée dépend de votre utilisation : comptez plusieurs minutes par point au repos. Laissez le Mac et son chargeur disponibles.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Annuler et rétablir l’alimentation") { Task { await model.perform(.cancelCycle) } }
                        .disabled(model.controlsBusy || model.protection?.ownedByCaller != true)
                } else {
                    Text("Le Mac utilise sa batterie tout en restant branché, puis reprend l’alimentation secteur à \(model.configuration.limit) %. Cette action est volontaire et peut être annulée.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Décharger vers \(model.configuration.limit) %") { Task { await model.perform(.discharge) } }
                        .disabled(!canStart || (model.snapshot?.percent ?? 0) <= model.configuration.limit)
                }
                if !model.supportsDischarge {
                    Label("Le contrôle de l’adaptateur n’est pas disponible avec le contrôleur actuellement détecté.", systemImage: "info.circle")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else if !model.active {
                    Text("Activez d’abord la protection dans Protection de la batterie.").foregroundStyle(.secondary)
                }
                Text("Si le secteur ne revient pas à l’arrivée, débranchez le câble puis rebranchez-le. C’est arrivé avec une alimentation de 30 W, pas avec un chargeur de 65 W.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Le Mac reste éveillé pendant la décharge. Fermer le capot, quitter MacCare ou une mesure devenue inconnue l’interrompent et rétablissent l’alimentation.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(12)
        }
    }
}
