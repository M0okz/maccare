import SwiftUI

struct PerformanceSettingsView: View {
    @AppStorage(PerformancePreferences.localSnapshotsKey)
    private var includeLocalSnapshots = PerformancePreferences.includeLocalSnapshotsDefault

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Libération de l’espace purgeable").font(.headline).accessibilityAddTraits(.isHeader)
            Toggle("Inclure les instantanés Time Machine locaux", isOn: $includeLocalSnapshots)
                .toggleStyle(.switch)
            Text("Autorise MacCare à demander à macOS de réduire les instantanés locaux, en complément des caches. Certains points de restauration présents sur ce Mac peuvent alors être supprimés définitivement. Les sauvegardes sur disque externe ou réseau ne sont pas visées.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Label(includeLocalSnapshots
                  ? "Activé : caches et instantanés locaux, après confirmation de chaque exécution."
                  : "Désactivé : seuls les caches sont concernés ; les instantanés locaux sont conservés.",
                  systemImage: includeLocalSnapshots ? "clock.arrow.circlepath" : "checkmark.shield")
                .font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            Text("Ce réglage ne lance aucune suppression automatique. Un changement s’applique aux prochaines actions, pas à une réduction déjà en cours.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(20)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}
