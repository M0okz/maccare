import SwiftUI
import AppKit

/// Icône réelle d'une application installée.
struct AppIcon: View {
    let app: AppInfo
    var size: CGFloat = 44

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

struct UninstallView: View {
    @ObservedObject var model: UninstallModel
    let layout: MainWindowLayout
    @State private var query = ""
    @State private var displayedReceipt: UninstallReceipt?
    @State private var focusedLeftoverID: String?

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                browser.modifier(DisplayAdjustedContent(layout: layout))
                    .frame(minWidth: 240 * layout.scale, idealWidth: 280 * layout.scale, maxWidth: 340 * layout.scale)
                VStack(spacing: 0) {
                    if model.showingLeftovers {
                        leftoverDetail
                    } else {
                        header
                        content
                    }
                }
                .modifier(DisplayAdjustedContent(layout: layout))
                .frame(minWidth: 330 * layout.scale, maxWidth: .infinity, maxHeight: .infinity)
            }
            if model.showingLeftovers { leftoversFooter.displayScaledBlock(layout.scale) }
            else if model.selectedApp != nil { footer.displayScaledBlock(layout.scale) }
        }
        .sheet(item: $displayedReceipt) { UninstallReceiptView(receipt: $0) }
        .onAppear { model.loadApps() }
    }

    private var browser: some View {
        let duplicateNames = Set(Dictionary(grouping: model.apps, by: { $0.name.lowercased() }).filter { $0.value.count > 1 }.keys)
        return VStack(alignment: .leading, spacing: Space.m) {
            Text("Gestionnaire d’applications").font(.headline).accessibilityAddTraits(.isHeader)
            Picker("Afficher", selection: $model.showingLeftovers) {
                Text("Applications").tag(false)
                Text("Résidus").tag(true)
            }.actionCursor().pickerStyle(.segmented)
                .disabled(model.isCleaning)
            if model.showingLeftovers {
                Text(leftoversSubtitle).font(AppFont.secondary).foregroundStyle(Theme.muted)
                Button(model.leftoversScanned ? "Actualiser les résidus" : "Analyser les résidus") {
                    model.scanLeftovers()
                }
                .buttonStyle(.actionPill).disabled(model.isScanningLeftovers || model.isCleaning)
                leftoverBrowser
            } else {
                searchField
                Text("\(filteredApps.count) applications").font(AppFont.caption).foregroundStyle(Theme.muted)
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredApps) { app in
                            Button { model.selectedApp = app } label: {
                                HStack(spacing: 10) {
                                    AppIcon(app: app, size: 30).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.name).font(AppFont.body).lineLimit(2)
                                        if duplicateNames.contains(app.name.lowercased()) {
                                            Text(app.url.deletingLastPathComponent().path)
                                                .font(AppFont.caption).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .background(model.selectedApp == app ? Theme.surface : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plainAction)
                            .accessibilityAddTraits(model.selectedApp == app ? [.isSelected] : [])
                            .disabled(model.isCleaning)
                        }
                        if filteredApps.isEmpty { Text("Aucune application ne correspond.").foregroundStyle(Theme.muted) }
                    }
                }
            }
        }.padding(Space.l)
    }

    private var focusedLeftover: LeftoverItem? {
        model.leftovers.first { $0.id == focusedLeftoverID } ?? model.leftovers.first
    }

    private var leftoverBrowser: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(model.leftovers) { leftover in
                    HStack(spacing: 8) {
                        Toggle("Retirer \(leftover.item.url.lastPathComponent)", isOn: Binding(
                            get: { model.leftoverSelection.contains(leftover.id) },
                            set: { on in
                                if on { model.leftoverSelection.insert(leftover.id) }
                                else { model.leftoverSelection.remove(leftover.id) }
                            }
                        )).actionCursor().toggleStyle(.checkbox).labelsHidden().disabled(model.isCleaning)
                        Button { focusedLeftoverID = leftover.id } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(leftover.item.url.lastPathComponent).font(AppFont.secondary).lineLimit(2)
                                Text(humanSize(leftover.item.size_bytes)).font(AppFont.caption).foregroundStyle(Theme.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plainAction)
                            .accessibilityLabel("Examiner \(leftover.item.url.lastPathComponent)")
                            .accessibilityAddTraits(focusedLeftover?.id == leftover.id ? [.isSelected] : [])
                    }
                    .padding(10)
                    .background(focusedLeftover?.id == leftover.id ? Theme.surface : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var leftoverDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                ScreenHeader(title: "Résidus", subtitle: "Examinez les fichiers laissés par des applications supprimées. Cochez uniquement ceux que vous souhaitez retirer.")
                if let leftover = focusedLeftover {
                    Text(leftover.item.url.lastPathComponent).font(.title2).accessibilityAddTraits(.isHeader)
                    LabeledContent("Type", value: leftover.kind)
                    LabeledContent("Éditeur présumé", value: leftover.owner)
                    LabeledContent("Taille", value: humanSize(leftover.item.size_bytes))
                    Text(leftover.item.url.path).font(AppFont.secondary).textSelection(.enabled)
                    Text("Cette détection repose sur les applications présentes sur le Mac. Vérifiez le contenu avant de le retirer.")
                        .font(AppFont.secondary).foregroundStyle(Theme.muted)
                    Button("Afficher dans le Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([leftover.item.url])
                    }.buttonStyle(.actionPill)
                } else {
                    Text(model.isScanningLeftovers ? "Recherche des résidus…" : "Aucun résidu à afficher.")
                        .foregroundStyle(Theme.muted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(Space.xl)
        }
    }

    // MARK: En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            ScreenHeader(
                title: model.selectedApp?.name ?? "Désinstalleur",
                subtitle: model.selectedApp == nil
                    ? "Choisissez une application pour examiner son paquet et ses données associées."
                    : "Vérifiez les éléments cochés avant de les retirer."
            )
            if let app = model.selectedApp {
                HStack(spacing: Space.m) {
                    AppIcon(app: app, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Application sélectionnée").font(AppFont.body.weight(.semibold))
                        Text(app.url.path)
                            .font(AppFont.secondary).foregroundStyle(Theme.muted)
                            .lineLimit(1).truncationMode(.middle).help(app.url.path)
                        Text(app.bundleId ?? "sans identifiant")
                            .font(AppFont.secondary).foregroundStyle(Theme.muted)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()

                }
            }
        }
        .padding(Space.xl)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.faint)
            TextField("Rechercher une application", text: $query)
                .textFieldStyle(.plain)
                .font(AppFont.body)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Theme.border))
        .frame(maxWidth: 360)
    }

    // MARK: Contenu

    @ViewBuilder
    private var content: some View {
        if model.selectedApp == nil {
            placeholder("hand.point.left", "Sélectionnez une application dans la liste pour examiner ses fichiers.")
        } else if model.isScanning {
            Spacer(); ProgressView("Recherche de l’application et de ses données…"); Spacer()
        } else if model.residuals.isEmpty {
            placeholder("trash.slash", model.statusMessage ?? "Aucun élément détecté pour cette application.")
        } else {
            list
        }
    }

    private var filteredApps: [AppInfo] {
        query.isEmpty ? model.apps : model.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var leftoversSubtitle: String {
        if model.isScanningLeftovers { return "Analyse de ~/Library…" }
        guard model.leftoversScanned else {
            return "Dossiers de préférences et de données laissés par des apps qui ne sont plus installées."
        }
        return model.leftovers.isEmpty
            ? "Aucun reste détecté."
            : "\(model.leftovers.count) \(pl(model.leftovers.count, "élément")) · \(humanSize(model.leftoverTotal))"
    }

    private var leftoversFooter: some View {
        HStack(spacing: Space.m) {
            Button("Tout cocher") { model.leftoverSelection = Set(model.leftovers.map(\.id)) }.buttonStyle(.actionPill).controlSize(.small).disabled(model.isCleaning || model.isScanningLeftovers)
            Button("Tout décocher") { model.leftoverSelection = [] }.buttonStyle(.actionPill).controlSize(.small).disabled(model.isCleaning)
            if let r = model.leftoverReport {
                Text(reportSummary(r)).font(AppFont.secondary).foregroundStyle(r.needsAttention ? Theme.warn : Theme.muted)
            }
            Spacer()
            if !model.leftoverSelection.isEmpty {
                Text("Sélection : \(humanSize(model.leftoverSelectedSize))").font(AppFont.secondary)
            }
            PrimaryButton(
                title: model.directDeleteEnabled ? "Supprimer définitivement" : "Déplacer vers la corbeille",
                systemImage: "trash",
                tint: model.directDeleteEnabled ? Theme.danger : ModuleColor.uninstall
            ) { model.cleanLeftovers() }
            .disabled(model.leftoverSelection.isEmpty || model.isCleaning)
            .opacity(model.leftoverSelection.isEmpty || model.isCleaning ? 0.5 : 1)
        }
        .padding(Space.l)
        .background(Theme.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func placeholder(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: Space.s) {
            Spacer()
            Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(Theme.faint)
            Text(text).font(AppFont.body).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(Space.xl)
    }

    private var detail: UninstallDetailPresentation? {
        guard let app = model.selectedApp else { return nil }
        return UninstallDetailPresentation(app: app, items: model.residuals,
                                           selection: model.selection, directDelete: model.directDeleteEnabled)
    }

    private var list: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        HStack {
                            Text("Application").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                            Spacer()
                            Text(detail.includesApplication ? "À désinstaller" : "Conservée")
                                .font(AppFont.secondary).foregroundStyle(Theme.muted)
                        }
                        if detail.applicationItems.isEmpty {
                            Text("Le paquet ne figure plus à cet emplacement.")
                                .font(AppFont.secondary).foregroundStyle(Theme.muted)
                        } else {
                            itemList(detail.applicationItems)
                        }
                    }
                    VStack(alignment: .leading, spacing: Space.s) {
                        HStack {
                            Text("Données associées").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                            Spacer()
                            if !detail.associatedItems.isEmpty {
                                let eligible = detail.associatedItems.filter { model.review?.use(of: $0)?.canRemove == true }
                                let ids = Set(eligible.map(\.id))
                                let selected = ids.isSubset(of: model.selection)
                                Button(selected ? "Tout décocher" : "Tout cocher") {
                                    if selected { model.selection.subtract(ids) } else { model.selection.formUnion(ids) }
                                }
                                .buttonStyle(.actionPill).controlSize(.small)
                                .disabled(ids.isEmpty || model.isCleaning)
                                .accessibilityHint("Données associées à cette application")
                            }
                            Text("\(detail.associatedItems.count) \(pl(detail.associatedItems.count, "élément"))")
                                .font(AppFont.secondary).foregroundStyle(Theme.muted)
                        }
                        if detail.associatedItems.isEmpty {
                            Text("Aucune donnée associée détectée.")
                                .font(AppFont.body).foregroundStyle(Theme.muted)
                        } else {
                            itemList(detail.associatedItems)
                        }
                    }
                }
                .padding(.horizontal, Space.xl).padding(.bottom, Space.l)
            }
        }
    }

    private func itemList(_ items: [ScanItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                if idx > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                let use = model.review?.use(of: item)
                Toggle(isOn: Binding(get: { model.selection.contains(item.id) }, set: { _ in toggle(item) })) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.displayName).font(AppFont.body)
                            if let use {
                                Text(use.reason).font(AppFont.secondary).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(item.path).font(AppFont.caption).foregroundStyle(Theme.faint)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Text(humanSize(item.size_bytes)).font(AppFont.body).monospacedDigit().foregroundStyle(Theme.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.actionCursor()
                .toggleStyle(.checkbox).padding(.horizontal, 14).padding(.vertical, 9)
                .disabled(model.isCleaning || model.isScanning || use?.canRemove != true)
                    .contextMenu {
                        Button("Afficher dans le Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        }
                    }
            }
        }
        .card()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let detail, !model.isScanning {
                Text(detail.consequence)
                    .font(AppFont.secondary)
                    .foregroundStyle(model.directDeleteEnabled && detail.hasSelection ? Theme.warn : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Space.m) {
                if model.isCleaning {
                    ProgressView().controlSize(.small)
                    Text("Retrait en cours…").font(AppFont.secondary)
                } else if let r = model.lastReport {
                    if let receipt = model.receipt {
                        Text(receipt.summary).font(AppFont.secondary).foregroundStyle(r.needsAttention ? Theme.warn : Theme.muted)
                        Button("Détails") { displayedReceipt = receipt }.buttonStyle(.actionPill).controlSize(.small)
                    }
                    if let failure = r.failed.first {
                        Text(failure.error).font(AppFont.caption).foregroundStyle(Theme.warn)
                            .lineLimit(2).help(failure.error)
                    }
                } else {
                    Text("\(model.residuals.count) \(pl(model.residuals.count, "élément")) — \(humanSize(model.totalSize))")
                        .font(AppFont.secondary).foregroundStyle(Theme.muted)
                }
                if let error = model.statusMessage { Text(error).foregroundStyle(Theme.warn).font(AppFont.caption) }
                Spacer(minLength: Space.s)
                if !model.selection.isEmpty {
                    Text("Sélection : \(humanSize(model.selectedSize))").font(AppFont.secondary)
                }
                PrimaryButton(
                    title: detail?.actionTitle ?? "Retirer la sélection",
                    systemImage: "trash",
                    tint: model.directDeleteEnabled ? Theme.danger : Theme.accent
                ) { model.cleanSelected() }
                .disabled(model.selection.isEmpty || model.isCleaning || model.isScanning)
                .opacity(model.selection.isEmpty || model.isCleaning || model.isScanning ? 0.5 : 1)
            }
        }
        .padding(Space.l)
        .background(Theme.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func toggle(_ item: ScanItem) {
        if model.selection.contains(item.id) { model.selection.remove(item.id) }
        else { model.selection.insert(item.id) }
    }

    private func reportSummary(_ r: RemovalReport) -> String { r.summary }
}
