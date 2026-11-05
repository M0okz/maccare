import SwiftUI
import ServiceManagement

/// Nettoyage système : journaux de /Library/Logs et /private/var/log, supprimés par l'assistant
/// privilégié. Suppression **définitive** : même gabarit de confirmation que « Corbeilles ».
struct SystemCleanView: View {
    @ObservedObject var model: SystemCleanModel
    @State private var confirming = false

    var body: some View {
        CleaningManagerLayout {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nettoyage système").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                    Text("Les journaux anciens de /Library/Logs et /private/var/log. Il faut un assistant que vous activez vous-même ; il ne supprime que des journaux de ces dossiers, jamais autre chose, et la suppression est définitive.").font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }

                if model.isEnabled {
                    VStack(alignment: .leading, spacing: Space.m) {
                        PrimaryButton(title: "Actualiser", systemImage: "arrow.clockwise", tint: ModuleColor.maint) { model.load() }
                            .disabled(model.isLoading || model.isRemoving)
                            .opacity(model.isLoading || model.isRemoving ? 0.5 : 1)
                        if model.hasLoaded {
                            Text("\(model.allItems.count) \(pl(model.allItems.count, "fichier")) · \(humanSize(model.totalSize))")
                                .font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        } detail: {
            content.padding(.top, 24)
        } footer: {
            if model.isEnabled && !model.allItems.isEmpty { footer }
        }
        .onAppear {
            model.refreshStatus()
            if model.isEnabled && !model.hasLoaded { model.load() }
        }
        .sheet(isPresented: $confirming) { confirmation }
    }

    // MARK: Contenu

    @ViewBuilder
    private var content: some View {
        if !model.isEnabled {
            ScrollView { activationCard.padding(.bottom, 24) }
        } else if model.isRemoving {
            VStack(spacing: Space.s) {
                Spacer()
                ProgressView("Suppression en cours…")
                Text("Ce qui est déjà supprimé ne peut pas être récupéré.")
                    .font(AppFont.caption).foregroundStyle(Theme.faint)
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isLoading && !model.hasLoaded {
            Spacer(); ProgressView("Lecture des journaux…"); Spacer()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if model.allItems.isEmpty { nothingToClean }
                    ForEach(SystemCleanModel.rules) { rule in
                        let items = model.itemsByRule[rule.id] ?? []
                        if !items.isEmpty { section(rule, items) }
                    }
                    if model.truncated {
                        Label("La liste est tronquée (limite de nombre ou de durée) : actualisez après un premier nettoyage.",
                              systemImage: "exclamationmark.circle").font(AppFont.secondary).foregroundStyle(Theme.warn)
                    }
                    if let msg = model.statusMessage {
                        Label(msg, systemImage: "exclamationmark.triangle.fill").font(AppFont.secondary).foregroundStyle(Theme.warn)
                    }
                    history
                    deactivate
                }
                .padding(.horizontal, Space.xl).padding(.bottom, Space.l)
            }
        }
    }

    private var nothingToClean: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "checkmark.circle").font(.system(size: 36)).foregroundStyle(Theme.ok)
            Text("Rien à nettoyer.").font(AppFont.body.weight(.semibold))
            Text("Aucun journal assez ancien dans ces dossiers : c'est un résultat normal.")
                .font(AppFont.secondary).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity).padding(Space.xl)
    }

    private func section(_ rule: SystemCleanModel.RuleDef, _ items: [SystemCleanModel.Item]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.title).font(AppFont.body.weight(.semibold))
                    Text(rule.detail).font(AppFont.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(humanSize(items.reduce(0) { $0 + $1.size_bytes })).font(AppFont.secondary.weight(.bold)).monospacedDigit()
            }
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    if idx > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    row(item)
                }
            }
            .card()
        }
    }

    private func row(_ item: SystemCleanModel.Item) -> some View {
        HStack(spacing: 11) {
            CheckBox(label: "Sélectionner le journal \(item.rel_path)", on: model.selection.contains(item.id)) { model.toggle(item) }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.rel_path).font(AppFont.secondary.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Text("Modifié le " + item.modifiedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(AppFont.caption).foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 8)
            Text(humanSize(item.size_bytes)).font(AppFont.secondary.weight(.bold)).monospacedDigit()
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(item) }
    }

    // MARK: Activation

    private var activationCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                ModuleIcon(symbol: "lock.shield.fill", color: ModuleColor.maint, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Assistant système").font(AppFont.body.weight(.semibold))
                    Text(model.statusText).font(AppFont.secondary).foregroundStyle(model.phase == .unavailable ? Theme.warn : Theme.muted)
                }
                Spacer()
            }
            Text("Ces journaux appartiennent au système : MacCare a besoin d'un assistant qui tourne avec des droits d'administrateur. Pour le nettoyage, il ne connaît que trois règles fixes (journaux de /Library/Logs, rapports de plantage et archives de /private/var/log), ne reçoit jamais de chemin de MacCare, et note chacune de ses actions dans un journal. Le même assistant sert aussi à certaines tâches d'entretien et au contrôle de charge de la batterie. Vous pouvez le désactiver à tout moment : ces fonctions s'arrêtent alors aussi.")
                .font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            actions
            if let msg = model.statusMessage {
                Label(msg, systemImage: "exclamationmark.triangle.fill").font(AppFont.secondary).foregroundStyle(Theme.warn)
            }
        }
        .padding(Space.l)
        .card()
        .padding(.horizontal, Space.xl)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var actions: some View {
        switch model.phase {
        case .off:
            PrimaryButton(title: "Activer le nettoyage système", systemImage: "lock.open.fill", tint: ModuleColor.maint) { model.enable() }
                .fixedSize()
        case .needsApproval:
            HStack(spacing: Space.m) {
                PrimaryButton(title: "Ouvrir les Réglages", systemImage: "gearshape.fill", tint: ModuleColor.maint) { model.openApproval() }
                    .fixedSize()
                Button("J'ai approuvé : revérifier") { model.refreshStatus(); if model.isEnabled { model.load() } }
                    .buttonStyle(LinkStyle()).font(AppFont.secondary)
            }
        default:
            EmptyView()
        }
    }

    private var deactivate: some View {
        HStack {
            Text("Assistant : \(model.statusText.lowercased()).").font(AppFont.caption).foregroundStyle(Theme.faint)
            Spacer()
            Button("Désactiver l'assistant") { model.disable() }.buttonStyle(LinkStyle()).font(AppFont.secondary)
        }
    }

    // MARK: Historique

    @ViewBuilder
    private var history: some View {
        if !model.journal.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("HISTORIQUE").font(AppFont.caption.weight(.semibold)).tracking(0.5).foregroundStyle(Theme.muted)
                VStack(spacing: 0) {
                    ForEach(Array(model.journal.prefix(10).enumerated()), id: \.element.id) { idx, e in
                        if idx > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                        HStack {
                            Text((e.parsedDate ?? .distantPast).formatted(date: .abbreviated, time: .shortened))
                                .font(AppFont.secondary).foregroundStyle(Theme.muted)
                            Text(model.title(forRule: e.rule)).font(AppFont.secondary.weight(.medium))
                            Spacer()
                            Text("\(e.removed ?? 0) \(pl(e.removed ?? 0, "supprimé")) · \(humanSize(e.freed_bytes ?? 0))")
                                .font(AppFont.secondary).foregroundStyle(Theme.muted)
                            if let r = e.refused, !r.isEmpty { PillBadge(text: "\(r.count) \(pl(r.count, "refusé"))", kind: .review) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                    }
                }
                .card()
            }
        }
    }

    // MARK: Pied et confirmation

    private var footer: some View {
        HStack(spacing: Space.m) {
            if let s = model.lastSummary {
                Text(s).font(AppFont.secondary).foregroundStyle(model.lastNeedsAttention ? Theme.warn : Theme.muted)
            }
            Spacer()
            if !model.selectedItems.isEmpty {
                Text("Sélection : \(humanSize(model.selectedSize))").font(AppFont.secondary)
            }
            PrimaryButton(title: "Supprimer…", systemImage: "trash.slash", tint: Theme.danger) { confirming = true }
                .disabled(model.selectedItems.isEmpty || model.isRemoving)
                .opacity(model.selectedItems.isEmpty || model.isRemoving ? 0.5 : 1)
        }
        .padding(Space.l)
        .background(Theme.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    /// « Annuler » est l'action par défaut (Entrée) et d'annulation (Échap) ; le bouton de suppression
    /// n'a aucun raccourci clavier.
    private var confirmation: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                Image(systemName: "exclamationmark.triangle.fill").font(AppFont.display).foregroundStyle(Theme.danger)
                Text("Supprimer définitivement ?").font(AppFont.emphasis.weight(.bold))
            }
            Text("\(model.selectedItems.count) \(pl(model.selectedItems.count, "fichier")) · \(humanSize(model.selectedSize)) de journaux système seront supprimés par l'assistant.")
                .font(AppFont.body).fixedSize(horizontal: false, vertical: true)
            Text("Cette action est irréversible : ces fichiers ne passent pas par la corbeille.")
                .font(AppFont.secondary.weight(.semibold)).foregroundStyle(Theme.danger)
            HStack {
                Spacer()
                Button("Annuler") { confirming = false }.keyboardShortcut(.defaultAction)
                Button(role: .destructive) {
                    confirming = false
                    model.removeSelected()
                } label: { Text("Supprimer définitivement") }
                    .tint(Theme.danger)
            }
        }
        .padding(Space.xl)
        .frame(width: 440)
        .onExitCommand { confirming = false }
    }
}
