import SwiftUI
import AppKit

struct ApplicationsUpdatesManager: View {
    @ObservedObject var model: UpdatesModel
    let apps: [AppInfo]
    let onBack: () -> Void
    @ScaledMetric(relativeTo: .title) private var applicationTitleSize: CGFloat = 24
    @State private var selectedID: String?
    @State private var sort = ApplicationUpdateSort.recent
    @State private var query = ""
    @State private var showSearch = false
    @State private var lastOpened: [URL: Date] = [:]
    @State private var copiedID: String?
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var entries: [ApplicationUpdateEntry] {
        ApplicationUpdatePresentation.entries(sources: model.sources, apps: apps, query: query, sort: sort, lastOpened: lastOpened)
    }
    private var selected: ApplicationUpdateEntry? { entries.first { $0.id == selectedID } ?? entries.first }
    private var sources: [UpdateSource] { model.sources.filter { ["cask", "mas", "netnewswire"].contains($0.key) } }

    var body: some View {
        VStack(spacing: 0) {
            ScreenToolbar(title: "Gestionnaire Applications") {
                Button(action: onBack) { Label("Retour", systemImage: "chevron.left") }
                    .buttonStyle(ToolbarActionButtonStyle()).keyboardShortcut(.cancelAction)
            } trailing: {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                            showSearch.toggle()
                            if !showSearch { query = "" }
                        }
                        searchFocused = showSearch
                    } label: { Image(systemName: "magnifyingglass").frame(width: 36, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel("Rechercher une mise à jour")
                    Picker("Trier par", selection: $sort) {
                        ForEach(ApplicationUpdateSort.allCases) { Text($0.title).tag($0) }
                    }.frame(width: 220)
                }
            }.padding(.horizontal, 24).frame(height: 56)
            Divider()
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    browser.frame(width: max(240, min(310, geometry.size.width * 0.28)))
                    Divider()
                    inspection.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            footer
        }
        .task(id: apps.map(\.url)) {
            let urls = apps.map(\.url)
            let values = await Task.detached(priority: .utility) {
                var result: [URL: Date] = [:]
                for url in urls {
                    if let date = NSMetadataItem(url: url)?.value(forAttribute: "kMDItemLastUsedDate") as? Date { result[url] = date }
                }
                return result
            }.value
            if !Task.isCancelled { lastOpened = values }
        }
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Outil de mise à jour").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
            Text("Retrouvez les nouvelles versions de vos applications et consultez leurs nouveautés.")
                .font(AppFont.secondary).foregroundStyle(Theme.muted)
            HStack {
                Text("\(entries.count) \(pl(entries.count, "mise")) à jour").font(AppFont.secondary).monospacedDigit()
                Spacer(minLength: 4)
                Button { model.checkApplications() } label: { Image(systemName: "arrow.clockwise").frame(width: 32, height: 32) }
                    .buttonStyle(.plain).disabled(model.isChecking).accessibilityLabel("Actualiser les mises à jour")
            }
            if showSearch {
                TextField("Rechercher une application", text: $query).textFieldStyle(.roundedBorder)
                    .focused($searchFocused).accessibilityLabel("Rechercher une application à mettre à jour")
            }
            if model.isChecking {
                HStack(spacing: 8) {
                    ScanActivityRing(lineWidth: 2).frame(width: 14, height: 14)
                    Text("Vérification en cours…").font(AppFont.secondary)
                }
            }
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(entries) { entry in
                        Button { selectedID = entry.id } label: {
                            HStack(spacing: 10) {
                                icon(entry).frame(width: 34, height: 34)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.item.name).font(AppFont.body.weight(.semibold)).lineLimit(2)
                                    Text(entry.versions.map { "Version \($0.current)" } ?? "Version non communiquée")
                                        .font(AppFont.secondary).foregroundStyle(Theme.muted).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: entry.source.key == "netnewswire" ? "sparkles" : "arrow.up.circle")
                                    .foregroundStyle(Theme.accent).accessibilityHidden(true)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                .background(selected?.id == entry.id ? Theme.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).accessibilityLabel("Examiner la mise à jour de \(entry.item.name)")
                            .accessibilityAddTraits(selected?.id == entry.id ? .isSelected : [])
                    }
                    if entries.isEmpty && !query.isEmpty {
                        Text("Aucun résultat pour cette recherche.").font(AppFont.secondary).foregroundStyle(Theme.muted).padding(.vertical, 12)
                    }
                    DisclosureGroup("État des sources") {
                        ForEach(sources) { source in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(source.title).font(AppFont.secondary.weight(.semibold))
                                Text(sourceStatus(source)).font(AppFont.secondary).foregroundStyle(Theme.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                        }
                    }.font(AppFont.secondary).padding(.top, 12)
                }
            }
        }.padding(20).frame(maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func icon(_ entry: ApplicationUpdateEntry) -> some View {
        if let url = entry.applicationURL(in: apps) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().accessibilityHidden(true)
        } else {
            Image(systemName: "app.fill").resizable().scaledToFit().foregroundStyle(Theme.accent).accessibilityHidden(true)
        }
    }

    private var inspection: some View {
        ScrollView {
            if let entry = selected {
                VStack(alignment: .leading, spacing: 24) {
                    Text(entry.item.name).font(.system(size: applicationTitleSize, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                        GridRow { Text("Source :"); Text(entry.sourceName).fontWeight(.semibold) }
                        GridRow {
                            Text("Version :")
                            if let versions = entry.versions {
                                HStack(spacing: 8) {
                                    Text(versions.current).fontWeight(.semibold)
                                    Image(systemName: "chevron.right").accessibilityHidden(true)
                                    Text(versions.available).fontWeight(.semibold)
                                }.accessibilityElement(children: .ignore).accessibilityLabel("\(versions.current) vers \(versions.available)")
                            } else { Text(entry.item.detail.isEmpty ? "Non communiquée" : entry.item.detail) }
                        }
                        if let value = entry.item.publicationDate {
                            GridRow { Text("Publication :"); Text(ApplicationUpdatePresentation.publicationLabel(value)) }
                        }
                        if let bytes = entry.item.downloadBytes {
                            GridRow { Text("Taille :"); Text(humanSize(bytes)).monospacedDigit() }
                        }
                    }.font(AppFont.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Nouveautés").font(AppFont.body.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        Text(ApplicationUpdatePresentation.displayNotes(entry.item.releaseNotes))
                            .font(AppFont.secondary).foregroundStyle(Theme.muted).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.isChecking ? "Vérification des mises à jour…" : ApplicationUpdateSummary(sources: model.sources).title)
                        .font(.title2).accessibilityAddTraits(.isHeader)
                    Text(query.isEmpty ? "Les résultats et leurs détails apparaîtront ici. Aucune mise à jour n’est installée automatiquement." : "Modifiez la recherche pour retrouver une application.")
                        .font(AppFont.body).foregroundStyle(Theme.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
            }
        }
    }

    private var footer: some View {
        AdaptiveActionRow {
            VStack(alignment: .leading, spacing: 5) {
                Text(selected.map { "\($0.item.name) · 1 mise à jour examinée" } ?? "Aucune mise à jour sélectionnée")
                    .font(AppFont.body.weight(.semibold))
                Text(copiedID != nil && copiedID == selected?.id ? "Commande copiée. Exécutez-la vous-même pour mettre à jour." : "Aucune installation automatique depuis MacCare.")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
            }
        } actions: {
            if let entry = selected {
                if entry.source.key == "mas" {
                    Button("Ouvrir l’App Store") { NSWorkspace.shared.open(AppStoreUpdates.storeURL) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .help("Ouvre l’App Store pour choisir les mises à jour à installer.")
                } else if let url = entry.item.applicationURL {
                    Button("Ouvrir pour mettre à jour") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .help("Ouvre l’application pour utiliser son mécanisme de mise à jour.")
                } else if !entry.source.command.isEmpty {
                    Button("Copier la commande") { model.copy(entry.source.command); copiedID = entry.id }
                        .buttonStyle(.borderedProminent).controlSize(.large).help(entry.source.command)
                }
            } else {
                Button("Vérifier les mises à jour") { model.checkApplications() }
                    .buttonStyle(.borderedProminent).disabled(model.isChecking)
            }
        }.padding(18).background(Theme.sidebar)
    }

    private func sourceStatus(_ source: UpdateSource) -> String {
        switch source.state {
        case .notInstalled: return "Source non disponible sur ce Mac"
        case .checking: return "Vérification en cours…"
        case .ok: return source.items.isEmpty ? "Aucune mise à jour détectée" : "\(source.items.count) \(pl(source.items.count, "mise")) à jour \(pl(source.items.count, "détectée"))"
        case .error(let message): return "Vérification incomplète : \(message)"
        }
    }
}
