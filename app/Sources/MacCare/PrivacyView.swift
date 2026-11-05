import SwiftUI

struct PrivacyView: View {
    @ObservedObject var model: PrivacyModel
    @State private var group: PrivacyGroup = .browsers
    @State private var query = ""
    @State private var confirmingRemoval = false
    @State private var confirmedDirect = false
    private var visible: [ScanItem] {
        group.items(in: model.items).filter { query.isEmpty || model.label(for: $0).localizedStandardContains(query) || $0.path.localizedStandardContains(query) }
    }
    private var busy: Bool { model.isScanning || model.isCleaning }
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
                    Text("\(model.selection.count) \(pl(model.selection.count, "élément")) \(pl(model.selection.count, "sélectionné")) · \(humanSize(model.selectedSize))").font(AppFont.body.weight(.semibold))
                    Text(model.lastReport?.summary ?? model.statusMessage ?? "Cookies, mots de passe et historique de navigation sont conservés.")
                        .font(AppFont.secondary).foregroundStyle(Theme.muted)
                }
            } actions: {
                if model.isCleaning { ProgressView("Retrait…") }
                Button(model.directDeleteEnabled ? "Supprimer définitivement…" : "Déplacer vers la corbeille…") {
                    confirmedDirect = model.directDeleteEnabled; confirmingRemoval = true
                }.buttonStyle(.borderedProminent).disabled(model.selection.isEmpty || busy)
            }
        }.sheet(isPresented: $confirmingRemoval) { removalConfirmation.modifier(ToolConfirmationStyle()) }
            .onChange(of: group) { _ in model.selectNone() }
    }
    private var browser: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Caches et données locales").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
            Text("Examinez les fichiers temporaires de vos navigateurs et les données locales de macOS.")
                .font(AppFont.secondary).foregroundStyle(Theme.muted)
            HStack {
                Text(model.hasScanned ? "\(model.items.count) \(pl(model.items.count, "emplacement"))" : "Prêt à analyser").font(AppFont.secondary)
                Spacer()
                Button { model.scan() } label: { Image(systemName: "arrow.clockwise").frame(width: 32, height: 32) }
                    .buttonStyle(.plain).disabled(busy).accessibilityLabel("Actualiser les données locales")
            }
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(PrivacyGroup.allCases) { value in
                        Button { group = value } label: {
                            HStack(spacing: 12) {
                                ModuleIcon(symbol: value == .browsers ? "globe" : "internaldrive.fill", color: ModuleColor.privacy, size: 32).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(value.title).font(AppFont.body.weight(.medium)).multilineTextAlignment(.leading)
                                    Text(humanSize(value.items(in: model.items).reduce(0) { $0 + $1.size_bytes })).font(AppFont.secondary).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 0)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(group == value ? Theme.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).disabled(busy).accessibilityAddTraits(group == value ? .isSelected : [])
                    }
                }
            }
        }.padding(20)
    }
    private var inspection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(group.title).font(AppFont.section).accessibilityAddTraits(.isHeader)
            Text(group.detail).font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            TextField("Rechercher un emplacement", text: $query).textFieldStyle(.roundedBorder)
            HStack {
                Button("Tout cocher ici") { model.selection = Set(visible.map(\.id)) }.disabled(busy || visible.isEmpty)
                Button("Tout décocher") { model.selectNone() }.disabled(busy || model.selection.isEmpty)
                Spacer()
                Text("\(visible.count) \(pl(visible.count, "emplacement"))").font(AppFont.secondary).foregroundStyle(Theme.muted)
            }
            if group == .local {
                Text("Retirer l’état des fenêtres empêche leur restauration. Les rapports retirés ne seront plus consultables.")
                    .font(AppFont.secondary).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
            }
            if model.isScanning {
                Spacer(); ProgressView("Analyse des données locales…").frame(maxWidth: .infinity); Spacer()
            } else if !model.hasScanned {
                Spacer()
                VStack(spacing: 18) {
                    Image(systemName: "hand.raised.fill").font(.system(size: 52)).foregroundStyle(ModuleColor.privacy).accessibilityHidden(true)
                    Text("Examinez vos données locales").font(AppFont.section)
                    Button("Analyser les données locales") { model.scan() }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if model.scanFailed { Label(model.statusMessage ?? "Analyse indisponible", systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warn) }
                        else if visible.isEmpty { Text("Aucun élément ne correspond à cette catégorie et à la recherche.").foregroundStyle(Theme.muted).padding(.vertical, 32) }
                        ForEach(visible) { item in
                            HStack(spacing: 14) {
                                Toggle(isOn: Binding(get: { model.selection.contains(item.id) }, set: { _ in model.toggle(item) })) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(model.label(for: item)).font(AppFont.body.weight(.semibold))
                                        Text(item.path).font(AppFont.caption).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle).help(item.path)
                                    }
                                }.toggleStyle(.checkbox).disabled(busy)
                                Spacer(minLength: 8)
                                Text(humanSize(item.size_bytes)).font(AppFont.body).monospacedDigit()
                            }.padding(.vertical, 16).contextMenu {
                                Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                            }
                            Divider()
                        }
                    }
                }
            }
        }.padding(24)
    }

    private var removalConfirmation: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(confirmedDirect ? "Supprimer définitivement ces données ?" : "Déplacer ces données vers la corbeille ?")
                .font(.system(size: 26, weight: .semibold)).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            Text("\(model.selectedItems.count) \(pl(model.selectedItems.count, "emplacement")) · \(humanSize(model.selectedSize))").font(AppFont.body)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.selectedItems) { item in Text(model.label(for: item)).font(AppFont.body) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: min(140, CGFloat(model.selectedItems.count) * 32))
            Text("Fermez les applications concernées avant de continuer. Les caches seront recréés au besoin.")
                .font(AppFont.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if model.selectedItems.contains(where: { model.tag(for: $0) == "Système" }) {
                Text("Les fenêtres des applications concernées ne seront plus restaurées à partir de cet état enregistré.")
                    .font(AppFont.body).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
            }
            if model.selectedItems.contains(where: { model.tag(for: $0) == "Rapports" }) {
                Text("Les rapports de diagnostic retirés ne seront plus consultables à cet emplacement.")
                    .font(AppFont.body).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
            }
            Text(confirmedDirect ? "Cette suppression est irréversible." : "Les éléments pourront être récupérés dans la corbeille.")
                .font(AppFont.body).foregroundStyle(confirmedDirect ? Theme.warn : Theme.muted)
            HStack {
                Spacer()
                Button("Annuler") { confirmingRemoval = false }.keyboardShortcut(.cancelAction)
                Button(confirmedDirect ? "Supprimer définitivement" : "Déplacer vers la corbeille", role: .destructive) {
                    confirmingRemoval = false
                    model.cleanSelected(directOverride: confirmedDirect)
                }
            }
        }.padding(28).frame(width: 520)
    }
}
