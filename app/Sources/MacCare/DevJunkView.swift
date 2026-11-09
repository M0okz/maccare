import SwiftUI

struct DevJunkView: View {
    @ObservedObject var model: DevJunkModel

    var body: some View {
        ManagerBrowserLayout {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Caches de développement").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                    Text("Caches de développement régénérables (builds, dépendances re-téléchargées). Les états non régénérables (VM, dépôts source) sont volontairement exclus.").font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: Space.m) {
                    PrimaryButton(title: "Rechercher", systemImage: "hammer", tint: ModuleColor.maint) {
                        model.scan()
                    }
                    .disabled(model.isScanning || model.isCleaning)
                    .opacity(model.isScanning || model.isCleaning ? 0.5 : 1)
                    if !model.items.isEmpty {
                        Text("\(model.items.count) \(pl(model.items.count, "cache")) · \(humanSize(model.totalSize))")
                            .font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } detail: {
            content.padding(.top, 24)
        } footer: {
            if !model.items.isEmpty { footer }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanning {
            Spacer(); ProgressView("Analyse des caches de dev…"); Spacer()
        } else if model.items.isEmpty {
            placeholder
        } else {
            list
        }
    }

    private var placeholder: some View {
        VStack(spacing: Space.s) {
            Spacer()
            Image(systemName: model.hasScanned ? "checkmark.circle" : "hammer")
                .font(.system(size: 36)).foregroundStyle(Theme.faint)
            Text(model.statusMessage
                 ?? (model.hasScanned ? "Aucun cache de dev connu trouvé." : "Lancez une recherche des caches de développement."))
                .font(AppFont.body).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(Space.xl)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { idx, item in
                    if idx > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    row(item)
                }
            }
            .card()
            .padding(.horizontal, Space.xl).padding(.bottom, Space.l)
        }
    }

    private func row(_ item: ScanItem) -> some View {
        HStack(spacing: 11) {
            CheckBox(label: "Sélectionner \(item.path)", on: model.selection.contains(item.id)) { model.toggle(item) }
            ModuleIcon(symbol: "shippingbox.and.arrow.backward.fill", color: ModuleColor.maint, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.label(for: item)).font(AppFont.body.weight(.semibold))
                Text(item.path).font(AppFont.caption).foregroundStyle(Theme.faint)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            PillBadge(text: model.tool(for: item), kind: .safe)
            Text(humanSize(item.size_bytes))
                .font(AppFont.body.weight(.bold)).monospacedDigit()
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(item) }
        .contextMenu {
            Button("Afficher dans le Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }

    private var footer: some View {
        AdaptiveActionRow {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(model.selectedItems.count) \(pl(model.selectedItems.count, "élément")) \(pl(model.selectedItems.count, "sélectionné"))").font(AppFont.body.weight(.semibold))
                HStack(spacing: Space.m) {
                    Button("Tout cocher") { model.selectAll() }.buttonStyle(LinkStyle())
                    Button("Tout décocher") { model.selectNone() }.buttonStyle(LinkStyle())
                }
                if let r = model.lastReport {
                    Text(reportSummary(r)).font(AppFont.secondary).foregroundStyle(r.needsAttention ? Theme.warn : Theme.muted)
                }
                if let msg = model.statusMessage {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(AppFont.secondary).foregroundStyle(Theme.warn)
                }
            }
        } actions: {
            HStack(spacing: Space.m) {
                if !model.selectedItems.isEmpty {
                    Text("Sélection : \(humanSize(model.selectedSize))").font(AppFont.secondary)
                }
                PrimaryButton(
                    title: model.directDeleteEnabled ? "Supprimer définitivement" : "Déplacer vers la corbeille",
                    systemImage: "trash",
                    tint: model.directDeleteEnabled ? Theme.danger : ModuleColor.maint
                ) { model.cleanSelected() }
                .disabled(model.selectedItems.isEmpty || model.isCleaning)
                .opacity(model.selectedItems.isEmpty || model.isCleaning ? 0.5 : 1)
            }
        }
        .padding(Space.l)
        .background(Theme.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func reportSummary(_ r: RemovalReport) -> String { r.summary }
}
