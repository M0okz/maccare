import MacCareBattery
import SwiftUI

struct AdditionalAlertSettingsView: View {
    let kind: AdditionalAlertKind
    let menuBarShown: Bool
    @AppStorage private var enabled: Bool
    init(kind: AdditionalAlertKind, menuBarShown: Bool) {
        self.kind = kind; self.menuBarShown = menuBarShown
        _enabled = AppStorage(wrappedValue: true, kind.enabledKey)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(kind.title, isOn: $enabled)
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if kind == .cycle && !BatteryCycle.calibrationAvailable {
                Text("L’étalonnage reste désactivé dans cette version. Les fins de décharge et de recharge ponctuelle à 100 % sont signalées.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button("Afficher un aperçu : \(kind.title)") {
                NotificationCenter.default.post(name: AdditionalAlertKind.previewNotification, object: nil, userInfo: ["kind": kind.rawValue])
            }.disabled(!menuBarShown)
            Text(menuBarShown ? "L’aperçu est fictif : il ne modifie ni la batterie, ni les rappels et ne ferme aucune application."
                             : "Activez la barre des menus pour afficher ces alertes.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var detail: String {
        switch kind {
        case .cpu: return "Une charge globale d’au moins 85 % pendant deux minutes déclenche une alerte. Les applications proposées peuvent être quittées normalement."
        case .protection: return "L’alerte apparaît si une protection attendue n’est plus confirmée pendant 30 secondes. Les pauses de charge normales et une désactivation volontaire ne déclenchent rien."
        case .cycle: return "Une notification signale chaque opération observée terminée avec succès, une fois la protection et le secteur confirmés. Les annulations et interruptions ne sont pas annoncées comme réussies."
        }
    }
}
