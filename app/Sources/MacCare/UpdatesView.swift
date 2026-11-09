import SwiftUI
import AppKit

/// Toutes les sources restent consultables depuis les accès directs et l’activité.
struct UpdatesView: View {
    @ObservedObject var model: UpdatesModel
    var applicationsOnly = false
    @State private var selectedItemID: String?

    private var sources: [UpdateSource] {
        applicationsOnly ? model.sources.filter { $0.isApplicationSource } : model.sources
    }
    private var selectedEntry: (source: UpdateSource, item: OutdatedItem)? {
        let entries = sources.flatMap { source in source.items.map { (source: source, item: $0) } }
        return entries.first { $0.item.id == selectedItemID } ?? entries.first
    }

    var body: some View {
        ManagerBrowserLayout {
            VStack(alignment: .leading, spacing: 16) {
                Text("Mises à jour").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                Text(applicationsOnly
                     ? "Consultez les mises à jour de vos applications et leurs notes de version."
                     : "Consultez les applications, Homebrew, l’App Store et macOS.")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Button("Vérifier", systemImage: "arrow.clockwise") {
                    if applicationsOnly { model.checkApplications() } else { model.check() }
                }.buttonStyle(.bordered).disabled(model.isChecking)
                if model.isChecking { ProgressView("Vérification…").font(AppFont.secondary) }
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(source.title).font(AppFont.body.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        Text(statusText(source)).font(AppFont.secondary).foregroundStyle(statusColor(source))
                        ForEach(source.items) { item in
                            Button { selectedItemID = item.id } label: {
                                Text(item.name).font(AppFont.body.weight(.medium)).lineLimit(2)
                                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).padding(10)
                                    .background(selectedEntry?.item.id == item.id ? Theme.accent.opacity(0.09) : .clear,
                                                in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain).accessibilityAddTraits(selectedEntry?.item.id == item.id ? .isSelected : [])
                        }
                    }
                }
            }
        } detail: {
            if let entry = selectedEntry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(entry.item.name).font(.title.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        Text("Source : \(entry.source.title)").font(AppFont.secondary).foregroundStyle(Theme.muted)
                        Text(entry.item.detail).font(AppFont.body).textSelection(.enabled)
                        if let date = entry.item.publicationDate { Text("Publication : \(date)") }
                        if let bytes = entry.item.downloadBytes { Text("Téléchargement : \(humanSize(bytes))") }
                        Text("Notes de version").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                        Text(entry.item.releaseNotes ?? "Les notes de version ne sont pas fournies par cette source.")
                            .textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
                }
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "arrow.triangle.2.circlepath").font(.largeTitle).foregroundStyle(Theme.muted).accessibilityHidden(true)
                    Text(model.isChecking ? "Vérification des mises à jour…" : model.hasChecked
                         ? "Aucune mise à jour à examiner dans les sources disponibles."
                         : "Vérifiez les mises à jour disponibles.")
                        .font(AppFont.body).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    Spacer()
                }.padding(26).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } footer: {
            AdaptiveActionRow {
                VStack(alignment: .leading, spacing: 5) {
                    Text(selectedEntry?.item.name ?? "Aucune mise à jour sélectionnée").font(AppFont.body.weight(.semibold))
                    Text(model.copiedCommand.map { "Copié : \($0)" } ?? "Aucune installation automatique depuis MacCare.")
                        .font(AppFont.secondary).foregroundStyle(Theme.muted)
                }
            } actions: {
                if let entry = selectedEntry { actions(source: entry.source, item: entry.item) }
            }.padding(18).background(Theme.sidebar)
        }
    }

    @ViewBuilder
    private func actions(source: UpdateSource, item: OutdatedItem) -> some View {
        if source.key == "mas" {
            Button("Ouvrir l’App Store") { NSWorkspace.shared.open(AppStoreUpdates.storeURL) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        } else if let url = item.downloadURL {
            Button("Accéder au téléchargement") { NSWorkspace.shared.open(url) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        } else if let url = item.applicationURL {
            Button("Ouvrir pour mettre à jour") { NSWorkspace.shared.open(url) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        } else if !source.command.isEmpty {
            Button("Copier la commande : \(source.command)") { model.copy(source.command) }
                .buttonStyle(.bordered).controlSize(.large)
        }
    }

    private func statusText(_ source: UpdateSource) -> String {
        switch source.state {
        case .notInstalled: return "non installé"
        case .checking: return "vérification…"
        case .ok: return source.items.isEmpty ? "à jour" : "\(source.items.count) \(pl(source.items.count, "mise")) à jour \(pl(source.items.count, "disponible"))"
        case .error(let message): return "erreur : \(message)"
        }
    }
    private func statusColor(_ source: UpdateSource) -> Color {
        switch source.state {
        case .ok: return source.items.isEmpty ? Theme.ok : Theme.warn
        case .error: return Theme.danger
        default: return Theme.muted
        }
    }
}
