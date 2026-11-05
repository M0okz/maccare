import SwiftUI

struct SmartScanView: View {
    @ObservedObject var model: SmartScanModel
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            switch model.stage {
            case .idle:
                idle
            case .scanning:
                scanning
            case .results, .cleaning:
                results
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: État initial

    private var idle: some View {
        VStack(spacing: Space.l) {
            Spacer()
            ModuleIcon(symbol: "sparkles", color: ModuleColor.privacy, size: 76)
            VStack(spacing: 6) {
                Text("Smart Scan").font(AppFont.display)
                Text("Analysez les catégories choisies dans vos réglages,\npuis décidez des éléments à nettoyer.")
                    .font(AppFont.body).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            PrimaryButton(title: "Analyser mon Mac", systemImage: "sparkles", tint: ModuleColor.privacy) {
                model.scan()
            }
            .padding(.top, Space.s)
            if let msg = model.statusMessage {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(AppFont.secondary).foregroundStyle(Theme.warn)
            }
            Spacer()
            Text("Analyse seule. Rien n'est supprimé sans votre validation. Suppression par la corbeille (réversible) par défaut.")
                .font(AppFont.caption).foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
                .padding(.bottom, Space.l)
        }
        .frame(maxWidth: 460)
        .padding(Space.xl)
    }

    // MARK: Scan en cours

    private var scanning: some View {
        AnalysisProgressView(title: "Analyse de votre Mac…", detail: model.currentLabel ?? "Recherche des éléments à examiner.", symbol: "sparkles", cancel: { model.cancelScan() }) {
            Text("\(model.liveEntries.formatted()) entrées lues · \(humanSize(model.liveBytes))")
            if model.foundCount > 0 { Text("\(model.foundCount) \(pl(model.foundCount, "élément")) \(pl(model.foundCount, "repéré"))") }
        }
    }

    // MARK: Résultats

    private var results: some View {
        VStack(spacing: 0) {
            summaryHeader
            if model.foundCount == 0 {
                allClean
            } else {
                ScrollView {
                    VStack(spacing: Space.m) {
                        ForEach(Array(model.groups.enumerated()), id: \.element.id) { idx, group in
                            if !group.items.isEmpty {
                                groupCard(group).appearIn(delay: Double(min(idx, 6)) * 0.04)
                            }
                        }
                    }
                    .id(model.foundCount)
                    .padding(.horizontal, Space.xl)
                    .padding(.bottom, Space.l)
                }
                footer
            }
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ScreenHeader(
                title: "Résultats du Smart Scan",
                subtitle: model.foundCount == 0
                    ? "Rien de récupérable pour l'instant."
                    : "Les éléments sûrs sont présélectionnés. Ceux à revoir restent décochés : à vous de décider."
            )
            if model.foundCount > 0 {
                HStack(spacing: Space.s) {
                    StatTile(title: "Sélectionné", value: humanSize(model.selectedSize), color: ModuleColor.privacy)
                    StatTile(title: "Éléments", value: "\(model.selectedItems.count)", color: Theme.accent)
                    StatTile(title: "Détecté", value: humanSize(model.foundSize), color: Theme.faint)
                }
            }
            if let r = model.lastReport {
                Label(reportSummary(r), systemImage: r.needsAttention ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(AppFont.secondary).foregroundStyle(r.needsAttention ? Theme.warn : Theme.ok)
            }
            if let msg = model.statusMessage {
                HStack(spacing: Space.m) {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(AppFont.secondary).foregroundStyle(Theme.warn)
                    // Après un arrêt, les résultats sont partiels : on peut reprendre l'analyse d'ici.
                    if model.wasCancelled {
                        Button("Relancer l'analyse") { model.scan() }
                            .buttonStyle(LinkStyle()).font(AppFont.secondary)
                    }
                }
            }
        }
        .padding(Space.xl)
        .padding(.bottom, Space.s)
    }

    private var allClean: some View {
        VStack(spacing: Space.s) {
            Spacer()
            // Un scan arrêté n'a pas tout examiné : ne pas affirmer que le Mac est propre.
            ModuleIcon(symbol: model.wasCancelled ? "pause.fill" : "checkmark",
                       color: model.wasCancelled ? Theme.warn : Theme.ok, size: 56)
            Text(model.wasCancelled ? "Analyse interrompue." : "Votre Mac est propre.")
                .font(AppFont.emphasis.weight(.semibold))
            Text(model.wasCancelled
                 ? "Rien n'a été trouvé avant l'arrêt ; le reste n'a pas été examiné."
                 : "Aucun cache ni log régénérable à récupérer.")
                .font(AppFont.body).foregroundStyle(Theme.muted)
            PrimaryButton(title: "Relancer un scan", systemImage: "arrow.clockwise", tint: ModuleColor.privacy) {
                model.scan()
            }
            .padding(.top, Space.s)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.xl)
    }

    private func groupCard(_ group: ScanGroup) -> some View {
        VStack(spacing: 0) {
            Button { toggleExpanded(group.id) } label: {
                HStack(spacing: Space.m) {
                    CheckBox(label: "Sélectionner la catégorie \(group.category.title)", on: model.isGroupFullySelected(group)) { model.toggleGroup(group) }
                    ModuleIcon(symbol: group.category.icon,
                               color: group.category.risk == .safe ? ModuleColor.clean : ModuleColor.maint, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.category.title).font(AppFont.body.weight(.semibold))
                        Text(groupSubtitle(group))
                            .font(AppFont.secondary).foregroundStyle(Theme.muted)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                    PillBadge(text: group.category.risk == .safe ? "Sûr" : "À revoir",
                              kind: group.category.risk == .safe ? .safe : .review)
                    Text(humanSize(group.size))
                        .font(AppFont.body.weight(.bold)).monospacedDigit()
                    Image(systemName: expanded.contains(group.id) ? "chevron.down" : "chevron.right")
                        .font(AppFont.caption.weight(.semibold)).foregroundStyle(Theme.faint)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded.contains(group.id) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                VStack(spacing: 0) {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                        ItemRow(item: item, on: model.selection.contains(item.id)) { model.toggle(item) }
                            .contextMenu {
                                Button("Afficher dans le Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                }
                            }
                    }
                }
            }
        }
        .card()
    }

    private var footer: some View {
        HStack(spacing: Space.m) {
            Button("Tout cocher") { model.selectAll() }.buttonStyle(LinkStyle())
            Button("Tout décocher") { model.selectNone() }.buttonStyle(LinkStyle())
            Spacer()
            if !model.selectedItems.isEmpty {
                Text("Sélection : \(humanSize(model.selectedSize))")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
            }
            PrimaryButton(
                title: model.directDeleteEnabled ? "Supprimer définitivement" : "Déplacer vers la corbeille",
                systemImage: "trash",
                tint: model.directDeleteEnabled ? Theme.danger : ModuleColor.privacy
            ) { model.cleanSelected() }
            .disabled(model.selectedItems.isEmpty || model.stage == .cleaning)
            .opacity(model.selectedItems.isEmpty || model.stage == .cleaning ? 0.5 : 1)
        }
        .padding(Space.l)
        .background(Theme.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func groupSubtitle(_ group: ScanGroup) -> String {
        let count = "\(group.items.count) \(pl(group.items.count, "élément"))"
        if group.category.risk == .safe { return "\(count) · régénérable" }
        return group.category.summary.isEmpty ? count : "\(count) · \(group.category.summary)"
    }

    private func toggleExpanded(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func reportSummary(_ r: RemovalReport) -> String { r.summary }
}
