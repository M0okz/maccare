import SwiftUI

struct AnalysisSettingsView: View {
    @StateObject private var preferences = ScanPreferences()
    @AppStorage(DeveloperTools.key) private var developerTools = DeveloperTools.defaultValue
    @State private var expanded: Set<String> = []

    private var available: [CleaningCategory] {
        CleaningCategory.all.filter { $0.audience == .everyone || developerTools }
    }
    private var groups: [String] { Array(Set(available.map(groupTitle))).sorted() }
    private var selected: Set<String> { Set(preferences.categories(from: available).map(\.id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Profil de nettoyage").font(.headline).accessibilityAddTraits(.isHeader)
            Picker("Profil de nettoyage", selection: Binding(
                get: { preferences.profile }, set: { preferences.select($0) }
            )) {
                ForEach(CleaningProfile.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(preferences.profile.detail).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(selected.count) \(pl(selected.count, "catégorie")) \(pl(selected.count, "incluse")) dans les analyses manuelles et planifiées du Smart Scan.")
                .font(.callout.weight(.medium))
            VStack(alignment: .leading, spacing: 12) {
                ForEach(groups, id: \.self) { title in
                    let categories = available.filter { groupTitle($0) == title }
                    DisclosureGroup(isExpanded: Binding(
                        get: { expanded.contains(title) },
                        set: { if $0 { expanded.insert(title) } else { expanded.remove(title) } }
                    )) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(categories) { category in categoryRow(category) }
                        }.padding(.leading, 20).padding(.vertical, 12)
                    } label: {
                        HStack {
                            Toggle(title, isOn: Binding(
                                get: { categories.allSatisfy { selected.contains($0.id) } },
                                set: { preferences.set(categories, enabled: $0, available: available) }
                            ))
                            .toggleStyle(.checkbox)
                            Spacer()
                            Text("\(categories.filter { selected.contains($0.id) }.count)/\(categories.count)")
                                .font(.caption).foregroundStyle(.secondary)

                        }
                    }
                    .accessibilityLabel(title)
                    if title != groups.last { Divider() }
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            if selected.isEmpty {
                Label("Sélectionnez au moins une catégorie pour lancer le Smart Scan.", systemImage: "info.circle")
                    .font(.callout)
            }
            Text("Les changements s’appliquent à la prochaine analyse. Analyser ne supprime rien. Le nettoyage par catégorie reste accessible indépendamment de ce profil.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func categoryRow(_ category: CleaningCategory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { selected.contains(category.id) },
                set: { preferences.set([category], enabled: $0, available: available) }
            )) {
                Label(category.title, systemImage: category.icon)
            }.toggleStyle(.checkbox)
            Text(category.summary).font(.callout).foregroundStyle(.secondary)
            Text(category.risk == .safe
                 ? "Faible risque · présélectionnée dans les résultats."
                 : "À examiner · sélection manuelle avant suppression.")
                .font(.caption).foregroundStyle(.secondary)
            Text(category.root).font(.caption.monospaced()).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func groupTitle(_ category: CleaningCategory) -> String {
        if category.audience == .developer { return "Développement" }
        if category.id.hasPrefix("cache.") || category.id.hasPrefix("logs.") { return "Caches et journaux" }
        if category.id.hasPrefix("downloads.") { return "Téléchargements" }
        if category.id.hasPrefix("ios.") { return "Sauvegardes d’appareils" }
        if category.id.hasPrefix("mail.") { return "Mail" }
        return "Préférences d’applications"
    }
}
