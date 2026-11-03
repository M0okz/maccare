import SwiftUI

struct AppUpdateSettingsView: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Rechercher automatiquement les mises à jour", isOn: $updater.automaticallyChecksForUpdates)
                .disabled(!updater.isAvailable)
            Text("MacCare consulte les releases GitHub. Vous choisissez quand installer une nouvelle version.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if let reason = updater.unavailableReason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let date = updater.lastCheckDate {
                    Text("Dernière recherche : \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Aucune recherche effectuée.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button("Rechercher les mises à jour…", action: updater.checkForUpdates)
                    .disabled(!updater.canCheckForUpdates)
            }
        }
    }
}
