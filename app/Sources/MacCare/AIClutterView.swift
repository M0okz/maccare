import SwiftUI
import AppKit

struct AIClutterView: View {
    @ObservedObject var model: AIClutterModel
    @State private var group: AIClutterGroup = .caches
    @State private var query = ""
    @State private var confirming = false
    @State private var sortBySize = true

    private var visible: [ScanItem] {
        model.items.filter {
            model.location(for: $0)?.group == group && (query.isEmpty ||
                [model.location(for: $0)?.application ?? "", model.location(for: $0)?.label ?? "", $0.path]
                    .contains { $0.localizedStandardContains(query) })
        }.sorted { sortBySize ? $0.size_bytes > $1.size_bytes : rowTitle($0).localizedStandardCompare(rowTitle($1)) == .orderedAscending }
    }
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    browser.frame(width: max(240, min(310, geometry.size.width * 0.28)))
                    Divider()
                    inspection.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            ToolManagerFooter {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(model.selection.count) \(pl(model.selection.count, "élément")) \(pl(model.selection.count, "sélectionné")) · \(humanSize(model.selectedSize))").font(AppFont.body.weight(.semibold)).monospacedDigit()
                    Text(model.lastReport?.summary ?? model.message ?? "Les éléments choisis seront déplacés vers la corbeille.")
                        .font(AppFont.secondary).foregroundStyle(Theme.muted)
                }
            } actions: {
                if model.isCleaning { ProgressView("Déplacement…") }
                Button("Déplacer vers la corbeille…") { confirming = true }
                    .buttonStyle(.borderedProminent).disabled(model.selection.isEmpty || model.busy)
            }
        }.sheet(isPresented: $confirming) { confirmation.modifier(ToolConfirmationStyle()) }
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Fichiers IA inutiles").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
            Text("Retrouvez les caches, les historiques et les modèles locaux de vos outils d’IA.")
                .font(AppFont.secondary).foregroundStyle(Theme.muted)
            HStack {
                Text(model.hasScanned ? "\(model.items.count) \(pl(model.items.count, "emplacement"))" : "Prêt à analyser").font(AppFont.secondary)
                Spacer()
                Button { model.scan() } label: { Image(systemName: "arrow.clockwise").frame(width: 32, height: 32) }
                    .buttonStyle(.plain).disabled(model.busy).accessibilityLabel("Actualiser les fichiers IA")
            }
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(AIClutterGroup.allCases) { category in
                        Button { group = category } label: {
                            HStack(spacing: 12) {
                                ModuleIcon(symbol: category == .caches ? "sparkles" : (category == .history ? "clock.arrow.circlepath" : "cpu"),
                                           color: category == .caches ? .green : (category == .history ? .orange : .purple), size: 32).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(category.title).font(AppFont.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                                    Text(humanSize(model.items.filter { model.location(for: $0)?.group == category }.reduce(0) { $0 + $1.size_bytes }))
                                        .font(AppFont.secondary).foregroundStyle(Theme.muted).monospacedDigit()
                                }
                                Spacer(minLength: 0)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(group == category ? Theme.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).disabled(model.busy).accessibilityAddTraits(group == category ? .isSelected : [])
                    }
                }
            }
            Text("Rien n’est sélectionné d’avance.").font(AppFont.secondary).foregroundStyle(Theme.muted)
        }.padding(20)
    }
    private var inspection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(group.title).font(AppFont.section).accessibilityAddTraits(.isHeader)
            Text(group.detail).font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                TextField("Rechercher une application ou un fichier", text: $query).textFieldStyle(.roundedBorder)
                Picker("Trier par", selection: $sortBySize) { Text("Taille").tag(true); Text("Nom").tag(false) }.frame(width: 150)
            }
            HStack {
                Button("Tout cocher ici") { model.selection.formUnion(visible.map(\.id)) }.disabled(model.busy || visible.isEmpty)
                Button("Tout décocher") { model.selection = [] }.disabled(model.busy || model.selection.isEmpty)
                Spacer()
                Text("\(visible.count) \(pl(visible.count, "élément"))").font(AppFont.secondary).foregroundStyle(Theme.muted)
            }
            if model.isScanning {
                Spacer(); ProgressView("Analyse des emplacements IA…").frame(maxWidth: .infinity); Spacer()
            } else if !model.hasScanned {
                Spacer()
                VStack(spacing: 18) {
                    Image(systemName: "sparkles.rectangle.stack.fill").font(.system(size: 52)).foregroundStyle(.green).accessibilityHidden(true)
                    Text("Faites le point sur vos fichiers IA").font(AppFont.section)
                    Button("Analyser les fichiers IA") { model.scan() }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if model.failed { Label(model.message ?? "Analyse indisponible", systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warn) }
                        else if visible.isEmpty { Text("Aucun élément accessible ne correspond à cette catégorie et à la recherche.").foregroundStyle(Theme.muted).padding(.vertical, 32) }
                        ForEach(visible) { item in
                            HStack(spacing: 14) {
                                Toggle("Retirer \(rowTitle(item))", isOn: Binding(get: { model.selection.contains(item.id) }, set: { value in
                                    if value { model.selection.insert(item.id) } else { model.selection.remove(item.id) }
                                })).labelsHidden().toggleStyle(.checkbox).disabled(model.busy)
                                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path)).resizable().scaledToFit().frame(width: 36, height: 36).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(rowTitle(item)).font(AppFont.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                    Text(item.path).font(AppFont.caption).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle).help(item.path)
                                }
                                Spacer(minLength: 0)
                                Text(humanSize(item.size_bytes)).font(AppFont.body).monospacedDigit()
                            }.padding(.vertical, 16).contextMenu {
                                Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                            }
                            Divider()
                        }
                    }
                }
            }
            Text("Emplacements connus de votre dossier personnel. Les modèles stockés ailleurs ne sont pas inclus.")
                .font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(24)
    }
    private func rowTitle(_ item: ScanItem) -> String { "\(model.location(for: item)?.application ?? "IA") · \(model.location(for: item)?.label ?? item.displayName)" }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Déplacer ces fichiers IA vers la corbeille ?").font(AppFont.section).accessibilityAddTraits(.isHeader)
            Text("\(model.selection.count) \(pl(model.selection.count, "élément")) · \(humanSize(model.selectedSize))").font(AppFont.emphasis)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.selectedItems) { item in
                        Text("\(model.location(for: item)?.application ?? "IA") · \(model.location(for: item)?.label ?? item.displayName)")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 160)
            Text("Quittez les applications et services IA concernés avant de continuer. Les fichiers pourront être récupérés dans la corbeille.")
            if model.selectedItems.contains(where: { model.location(for: $0)?.group == .history }) {
                Text("Les conversations et historiques locaux sélectionnés ne seront plus disponibles dans l’application.").foregroundStyle(Theme.warn)
            }
            if model.selectedItems.contains(where: { model.location(for: $0)?.group == .models }) {
                Text("Les modèles sélectionnés devront être téléchargés à nouveau. Pour Ollama, toute la bibliothèque locale sera déplacée.").foregroundStyle(Theme.warn)
            }
            HStack {
                Spacer()
                Button("Annuler") { confirming = false }.keyboardShortcut(.cancelAction)
                Button("Déplacer vers la corbeille", role: .destructive) { confirming = false; model.trashSelected() }
            }
        }.font(AppFont.body).padding(28).frame(width: 560)
    }
}
