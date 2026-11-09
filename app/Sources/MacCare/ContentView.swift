import ServiceManagement
import SwiftUI
import UserNotifications

struct CleaningView: View {
    @ObservedObject var model: ReviewModel

    var body: some View {
        ManagerBrowserLayout {
            VStack(alignment: .leading, spacing: 14) {
                Text("Par catégorie").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                Text("Choisissez une catégorie, puis examinez les éléments avant de les cocher.")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
                ForEach(model.categories) { category in
                    Button { model.category = category } label: {
                        Label(category.title, systemImage: category.icon)
                            .font(AppFont.body.weight(.medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).padding(10)
                            .background(model.category == category ? Theme.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).disabled(model.isScanning || model.isCleaning)
                        .accessibilityAddTraits(model.category == category ? .isSelected : [])
                }
            }
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(model.category.title).font(AppFont.pageTitle).accessibilityAddTraits(.isHeader)
                    Text(model.category.summary).font(AppFont.body).foregroundStyle(Theme.muted)
                    Text(model.category.root).font(AppFont.secondary).foregroundStyle(Theme.muted).textSelection(.enabled)
                    Button("Analyser la catégorie", systemImage: "magnifyingglass") { model.scan() }
                        .buttonStyle(.bordered).controlSize(.large).disabled(model.isScanning || model.isCleaning)
                }.padding(24)
                content
            }
        } footer: { footer }
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanning {
            Spacer()
            ProgressView("Analyse…")
            Spacer()
        } else if model.items.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var emptyState: some View {
        VStack(spacing: Space.s) {
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 36)).foregroundStyle(Theme.faint)
            Text(model.statusMessage ?? "Lancez un scan pour voir les éléments récupérables.")
                .font(AppFont.body).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.xl)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { idx, item in
                    if idx > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    ItemRow(
                        item: item,
                        on: model.selection.contains(item.id),
                        why: "règle \(item.reason)"
                    ) { toggle(item) }
                    .contextMenu {
                        Button("Exclure définitivement") { model.exclude(item) }
                        Button("Afficher dans le Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        }
                    }
                }
            }
            .card()
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.l)
        }
    }

    private var footer: some View {
        AdaptiveActionRow {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(model.selection.count) \(pl(model.selection.count, "élément")) \(pl(model.selection.count, "sélectionné"))")
                    .font(AppFont.body.weight(.semibold))
                if let r = model.lastReport {
                    Text(reportSummary(r)).font(AppFont.secondary).foregroundStyle(r.needsAttention ? Theme.warn : Theme.muted)
                } else {
                    Text("\(model.items.count) \(pl(model.items.count, "élément")) — \(humanSize(model.totalSize)) au total")
                        .font(AppFont.secondary).foregroundStyle(Theme.muted)
                }
            }
        } actions: {
            HStack(spacing: Space.m) {
                if !model.selection.isEmpty {
                    Text("Sélection : \(humanSize(model.selectedSize))").font(AppFont.secondary)
                }
                PrimaryButton(
                    title: model.directDelete ? "Supprimer définitivement" : "Déplacer vers la corbeille",
                    systemImage: "trash",
                    tint: model.directDelete ? Theme.danger : Theme.accent
                ) { model.cleanSelected() }
                .disabled(model.selection.isEmpty || model.isCleaning)
                .opacity(model.selection.isEmpty || model.isCleaning ? 0.5 : 1)
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
