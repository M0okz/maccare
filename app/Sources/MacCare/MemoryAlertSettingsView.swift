import SwiftUI

struct MemoryAlertSettingsView: View {
    let menuBarShown: Bool
    @AppStorage(MemoryAlertPolicy.enabledKey) private var enabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("M’avertir lorsque la pression mémoire est élevée", isOn: $enabled)
            Text("MacCare signale une pression mémoire élevée persistante ou critique et propose jusqu’à trois applications à fermer. Un rappel au maximum par jour, avec les reports d’une journée ou d’une semaine.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Quitter demande une fermeture normale. Tout forcer à quitter nécessite une confirmation et concerne uniquement les applications affichées.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !menuBarShown {
                Text("Activez la barre des menus pour recevoir ces alertes.").font(.callout).foregroundStyle(.secondary)
            }
            Button("Afficher un aperçu de l’alerte mémoire") {
                NotificationCenter.default.post(name: MemoryAlertPolicy.previewNotification, object: nil)
            }.disabled(!menuBarShown)
            Text("L’aperçu utilise un exemple fictif. Il ne ferme aucune application et ne modifie pas les rappels.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
