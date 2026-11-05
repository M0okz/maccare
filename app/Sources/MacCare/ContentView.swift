import ServiceManagement
import SwiftUI
import UserNotifications

struct CleaningView: View {
    @ObservedObject var model: ReviewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.l) {
                ScreenHeader(
                    title: "Nettoyage · \(model.category.title)",
                    subtitle: "\(model.category.root) · chaque ligne indique pourquoi elle est proposée. Rien n'est coché d'office."
                )

                HStack(spacing: Space.m) {
                    Picker("Catégorie", selection: $model.category) {
                        ForEach(model.categories) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)

                    Spacer()

                    PrimaryButton(title: "Scanner", systemImage: "magnifyingglass") { model.scan() }
                        .disabled(model.isScanning || model.isCleaning)
                        .opacity(model.isScanning || model.isCleaning ? 0.5 : 1)
                }
            }
            .padding(Space.xl)
            .padding(.bottom, 0)

            content

            footer
        }
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
        HStack(spacing: Space.m) {
            if let r = model.lastReport {
                Text(reportSummary(r)).font(AppFont.secondary).foregroundStyle(r.needsAttention ? Theme.warn : Theme.muted)
            } else {
                Text("\(model.items.count) \(pl(model.items.count, "élément")) — \(humanSize(model.totalSize)) au total")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
            }
            Spacer()
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
