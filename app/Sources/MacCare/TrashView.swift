import SwiftUI

struct TrashView: View {
    @ObservedObject var model: TrashModel
    @ObservedObject var permissions: PermissionsModel
    @State private var confirming = false

    var body: some View {
        ManagerBrowserLayout {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Corbeilles").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                    Text("Sélectionnez les corbeilles à vider. Le vidage est définitif et demande confirmation.").font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: Space.m) {
                    PrimaryButton(title: "Actualiser", systemImage: "arrow.clockwise", tint: ModuleColor.clean) { model.load() }
                        .disabled(model.isLoading || model.isEmptying)
                        .opacity(model.isLoading || model.isEmptying ? 0.5 : 1)
                    if model.hasLoaded && !model.bins.isEmpty {
                        Text("\(model.bins.count) \(pl(model.bins.count, "corbeille")) · \(humanSize(model.totalSize))")
                            .font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } detail: {
            content.padding(.top, 24)
        } footer: {
            if !model.bins.isEmpty { footer }
        }
        .onAppear { if !model.hasLoaded { model.load() } }
        .sheet(isPresented: $confirming) { confirmation }
    }

    @ViewBuilder
    private var content: some View {
        if model.isEmptying {
            VStack(spacing: Space.s) {
                Spacer()
                ProgressView("Vidage en cours…")
                Button("Arrêter") { model.cancelEmptying() }
                    .buttonStyle(LinkStyle())
                    .padding(.top, Space.s)
                Text("Ce qui est déjà supprimé ne peut pas être récupéré.")
                    .font(AppFont.caption).foregroundStyle(Theme.faint)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isLoading && !model.hasLoaded {
            Spacer(); ProgressView("Mesure des corbeilles…"); Spacer()
        } else if model.bins.isEmpty {
            VStack(spacing: Space.s) {
                Spacer()
                Image(systemName: "trash").font(.system(size: 36)).foregroundStyle(Theme.faint)
                Text(model.statusMessage ?? "Aucune corbeille trouvée.")
                    .font(AppFont.body).foregroundStyle(Theme.muted)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.bins.enumerated()), id: \.element.id) { idx, bin in
                        if idx > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                        row(bin)
                    }
                }
                .card()
                .padding(.horizontal, Space.xl).padding(.bottom, Space.l)
            }
        }
    }

    private func row(_ b: TrashBin) -> some View {
        HStack(spacing: 11) {
            if b.readable && b.items > 0 {
                CheckBox(label: "Sélectionner la corbeille \(b.label)", on: model.selection.contains(b.path)) { model.toggle(b) }
            } else {
                Color.clear.frame(width: 18, height: 18)
            }
            ModuleIcon(symbol: b.label == "Corbeille" ? "trash.fill" : "externaldrive.fill", color: ModuleColor.clean, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(b.label == "Corbeille" ? "Corbeille du Mac" : "Corbeille de « \(b.label) »")
                    .font(AppFont.body.weight(.semibold))
                Text(b.path).font(AppFont.caption).foregroundStyle(Theme.faint)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if !b.readable {
                PillBadge(text: "Autorisation manquante", kind: .review)
                Button("Configurer") { permissions.reopen() }.buttonStyle(LinkStyle())
            } else if b.items == 0 {
                Text("Vide").font(AppFont.secondary).foregroundStyle(Theme.muted)
            } else {
                Text("\(b.items) \(pl(b.items, "élément"))").font(AppFont.secondary).foregroundStyle(Theme.muted)
                Text((b.measured ? "" : "≥ ") + humanSize(b.size_bytes))
                    .font(AppFont.body.weight(.bold)).monospacedDigit()
                    .frame(minWidth: 72, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(b) }
    }

    private var footer: some View {
        AdaptiveActionRow {
            VStack(alignment: .leading, spacing: 8) {
                if let s = model.lastSummary {
                    Text(s).font(AppFont.secondary).foregroundStyle(model.lastNeedsAttention ? Theme.warn : Theme.muted)
                } else if let msg = model.statusMessage {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(AppFont.secondary).foregroundStyle(Theme.warn)
                } else if model.hasUnreadable {
                    Text("Une corbeille n'est pas lisible : accordez l'Accès complet au disque pour la mesurer.")
                        .font(AppFont.secondary).foregroundStyle(Theme.muted)
                } else {
                    Text(model.selectedBins.isEmpty ? "Sélectionnez une corbeille." : "Vidage définitif après confirmation.")
                        .font(AppFont.secondary).foregroundStyle(Theme.muted)
                }
            }
        } actions: {
            HStack(spacing: Space.m) {
                if !model.selectedBins.isEmpty {
                    Text("Sélection : \(humanSize(model.selectedSize))").font(AppFont.secondary)
                }
                PrimaryButton(title: "Vider…", systemImage: "trash.slash", tint: Theme.danger) {
                    // Le contenu est relu avant de demander confirmation : la feuille annonce l'état actuel.
                    model.load()
                    confirming = true
                }
                    .disabled(model.selectedBins.isEmpty || model.isEmptying)
                    .opacity(model.selectedBins.isEmpty || model.isEmptying ? 0.5 : 1)
            }
        }
        .padding(Space.l)
        .background(Theme.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    /// Confirmation : « Annuler » est l'action par défaut (Entrée) et d'annulation (Échap) ; le
    /// bouton de vidage n'a aucun raccourci clavier.
    private var confirmation: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                Image(systemName: "exclamationmark.triangle.fill").font(AppFont.display).foregroundStyle(Theme.danger)
                Text("Vider définitivement ?").font(AppFont.emphasis.weight(.bold))
            }
            if model.isLoading {
                ProgressView("Vérification du contenu…").font(AppFont.body)
            } else if model.selectedBins.isEmpty {
                Text("La corbeille sélectionnée a changé ou est désormais vide.").font(AppFont.body)
            } else {
                Text("\(model.selectedItems) \(pl(model.selectedItems, "élément")) · \(humanSize(model.selectedSize)) seront supprimés définitivement de : \(model.selectedBins.map(\.label).joined(separator: ", ")).")
                    .font(AppFont.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Cette action est irréversible : ces éléments ne pourront pas être récupérés.")
                .font(AppFont.secondary.weight(.semibold)).foregroundStyle(Theme.danger)
            HStack {
                Spacer()
                Button("Annuler") { confirming = false }
                    .keyboardShortcut(.defaultAction)
                Button(role: .destructive) {
                    confirming = false
                    model.emptySelected()
                } label: {
                    Text("Vider définitivement")
                }
                .tint(Theme.danger)
                .disabled(model.isLoading || model.selectedBins.isEmpty)
            }
        }
        .padding(Space.xl)
        .frame(width: 440)
        .onExitCommand { confirming = false }
    }
}
