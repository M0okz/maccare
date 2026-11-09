import SwiftUI

struct SmartScanView: View {
    @ObservedObject var model: SmartScanModel
    @State private var focusedGroup: String?

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
        ManagerBrowserLayout {
            VStack(alignment: .leading, spacing: 14) {
                Text("Résultats de l’analyse").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                Text("Examinez une catégorie, puis cochez les éléments à nettoyer. Les catégories sûres sont présélectionnées.")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
                Text("\(model.foundCount) \(pl(model.foundCount, "élément")) · \(humanSize(model.foundSize))")
                    .font(AppFont.secondary).monospacedDigit()
                ForEach(model.groups.filter { !$0.items.isEmpty }) { group in
                    HStack(spacing: 9) {
                        CheckBox(label: "Sélectionner la catégorie \(group.category.title)", on: model.isGroupFullySelected(group)) { model.toggleGroup(group) }
                            .disabled(model.stage == .cleaning)
                        Button { focusedGroup = group.id } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(group.category.title, systemImage: group.category.icon).font(AppFont.body.weight(.medium))
                                Text(humanSize(group.size)).font(AppFont.secondary).foregroundStyle(Theme.muted).monospacedDigit()
                            }.frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        }
                        .buttonStyle(.plain).accessibilityAddTraits(selectedGroup?.id == group.id ? .isSelected : [])
                    }.padding(10).background(selectedGroup?.id == group.id ? Theme.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }
            }
        } detail: {
            if model.foundCount == 0 { allClean }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let group = selectedGroup {
                            Text(group.category.title).font(AppFont.pageTitle).accessibilityAddTraits(.isHeader)
                            Text(group.category.summary).font(AppFont.body).foregroundStyle(Theme.muted)
                            Text(groupSubtitle(group)).font(AppFont.secondary).foregroundStyle(Theme.muted)
                            PillBadge(text: group.category.risk == .safe ? "Sûr" : "À revoir", kind: group.category.risk == .safe ? .safe : .review)
                            VStack(spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, item in
                                    if idx > 0 { Divider() }
                                    ItemRow(item: item, on: model.selection.contains(item.id)) { model.toggle(item) }
                                        .disabled(model.stage == .cleaning)
                                        .contextMenu {
                                            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                                        }
                                }
                            }.card()
                        }
                        if let report = model.lastReport {
                            Text(reportSummary(report)).font(AppFont.secondary).foregroundStyle(report.needsAttention ? Theme.warn : Theme.ok)
                        }
                        if let message = model.statusMessage {
                            Label(message, systemImage: "exclamationmark.triangle").font(AppFont.secondary).foregroundStyle(Theme.warn)
                            if model.wasCancelled {
                                Button("Relancer l’analyse") { model.scan() }.buttonStyle(.bordered)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(26)
                }
            }
        } footer: { footer }
    }

    private var selectedGroup: ScanGroup? {
        model.groups.first { $0.id == focusedGroup && !$0.items.isEmpty }
            ?? model.groups.first { !$0.items.isEmpty }
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

    private var footer: some View {
        AdaptiveActionRow {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(model.selectedItems.count) \(pl(model.selectedItems.count, "élément")) \(pl(model.selectedItems.count, "sélectionné"))").font(AppFont.body.weight(.semibold))
                HStack(spacing: Space.m) {
                    Button("Tout cocher") { model.selectAll() }.buttonStyle(LinkStyle())
                    Button("Tout décocher") { model.selectNone() }.buttonStyle(LinkStyle())
                }
            }
        } actions: {
            HStack(spacing: Space.m) {
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

    private func reportSummary(_ r: RemovalReport) -> String { r.summary }
}
