import SwiftUI
import AppKit

struct UpdatesView: View {
    @ObservedObject var model: UpdatesModel
    var applicationsOnly = false
    private var sources: [UpdateSource] {
        applicationsOnly ? model.sources.filter { ["cask", "mas", "netnewswire"].contains($0.key) } : model.sources
    }
    @State private var selectedItemID: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.l) {
                ScreenHeader(
                    title: "Mises à jour",
                    subtitle: applicationsOnly
                        ? "Consultez les mises à jour de vos applications et leurs notes de version. Aucune installation automatique."
                        : "État des mises à jour via Homebrew, l’App Store, Sparkle (NetNewsWire) et macOS. MacCare n'installe rien : copiez la commande et lancez-la vous-même."
                )
                HStack(spacing: Space.m) {
                    PrimaryButton(title: "Vérifier", systemImage: "arrow.triangle.2.circlepath", tint: ModuleColor.updates) { if applicationsOnly { model.checkApplications() } else { model.check() } }
                        .disabled(model.isChecking)
                        .opacity(model.isChecking ? 0.5 : 1)
                    if model.isChecking { ProgressView().scaleEffect(0.6).frame(width: 16, height: 16) }
                    Spacer()
                    if let c = model.copiedCommand {
                        Label("Copié : \(c)", systemImage: "checkmark").font(AppFont.secondary).foregroundStyle(Theme.ok)
                    }
                }
            }
            .padding(Space.xl).padding(.bottom, Space.s)

            if !model.hasChecked && !model.isChecking {
                placeholder
            } else {
                HSplitView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.m) {
                            ForEach(sources) { source in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(source.title).font(AppFont.body.weight(.semibold))
                                        .accessibilityAddTraits(.isHeader)
                                    Text(statusText(source)).font(AppFont.caption).foregroundStyle(statusColor(source))
                                    ForEach(source.items) { item in
                                        Button { selectedItemID = item.id } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.name).font(AppFont.body.weight(.medium))
                                                Text(item.detail).font(AppFont.caption).foregroundStyle(Theme.muted)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                            .background(selectedItemID == item.id ? Theme.surface : Color.clear,
                                                        in: RoundedRectangle(cornerRadius: 8))
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }.padding(Space.l)
                    }.frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
                    ScrollView {
                        if let entry = selectedEntry {
                            VStack(alignment: .leading, spacing: Space.l) {
                                Text(entry.item.name).font(.title).accessibilityAddTraits(.isHeader)
                                Text("Source : \(entry.source.title)").font(AppFont.secondary)
                                Text(entry.item.detail).font(AppFont.body).textSelection(.enabled)
                                if let date = entry.item.publicationDate { Text("Publication : \(date)") }
                                if let bytes = entry.item.downloadBytes { Text("Téléchargement : \(humanSize(bytes))") }
                                Text("Notes de version").font(.headline).accessibilityAddTraits(.isHeader)
                                Text(entry.item.releaseNotes ?? "Les notes de version ne sont pas fournies par cette source.")
                                    .textSelection(.enabled)
                                if let url = entry.item.applicationURL {
                                    Button("Ouvrir NetNewsWire pour mettre à jour") { NSWorkspace.shared.open(url) }
                                        .buttonStyle(.borderedProminent)
                                } else if !entry.source.command.isEmpty {
                                    Button("Copier la commande : \(entry.source.command)") { model.copy(entry.source.command) }
                                        .buttonStyle(SecondaryActionButtonStyle())
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(Space.xl)
                        } else {
                            Text("Sélectionnez une mise à jour pour consulter ses détails.")
                                .foregroundStyle(Theme.muted).padding(Space.xl)
                        }
                    }.frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                }

            }
        }
    }

    private var selectedEntry: (source: UpdateSource, item: OutdatedItem)? {
        let entries = sources.flatMap { source in source.items.map { (source: source, item: $0) } }
        return entries.first { $0.item.id == selectedItemID } ?? entries.first
    }

    private var placeholder: some View {
        VStack(spacing: Space.s) {
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 36)).foregroundStyle(Theme.faint)
            Text("Vérifiez les mises à jour disponibles.").font(AppFont.body).foregroundStyle(Theme.muted)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(Space.xl)
    }

    private func statusText(_ s: UpdateSource) -> String {
        switch s.state {
        case .notInstalled: return "non installé"
        case .checking: return "vérification…"
        case .ok: return s.items.isEmpty ? "à jour" : "\(s.items.count) \(pl(s.items.count, "mise")) à jour \(pl(s.items.count, "disponible"))"
        case .error(let m): return "erreur : \(m)"
        }
    }
    private func statusColor(_ s: UpdateSource) -> Color {
        switch s.state {
        case .ok: return s.items.isEmpty ? Theme.ok : Theme.warn
        case .error: return Theme.danger
        default: return Theme.muted
        }
    }
}
