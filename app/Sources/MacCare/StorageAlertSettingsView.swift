import SwiftUI

struct StorageAlertSettingsView: View {
    let menuBarShown: Bool
    @AppStorage(StorageAlertPolicy.enabledKey) private var enabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("M’avertir lorsque l’espace disque est faible", isOn: $enabled)
            Text("Une bulle sous l’icône MacCare signale 10 % d’espace disponible ou moins, ou moins de 10 Go sur le disque de démarrage. Un rappel au maximum par jour, avec la possibilité d’ignorer l’alerte pendant une journée ou une semaine.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !menuBarShown {
                Text("Activez la barre des menus pour recevoir ces alertes.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button("Afficher un aperçu") {
                NotificationCenter.default.post(name: StorageAlertPolicy.previewNotification, object: nil)
            }.disabled(!menuBarShown)
            Text("L’aperçu utilise un exemple fictif et ne modifie pas vos rappels. Ouvrir MacCare ne lance aucun nettoyage.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
