import SwiftUI

struct SimulatorsView: View {
    @ObservedObject var model: SimulatorsModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.l) {
                ScreenHeader(
                    title: "Simulateurs",
                    subtitle: "Simulateurs et systèmes de simulation téléchargés par Xcode. Supprimer un simulateur efface ses apps et données de test ; MacCare passe par l'outil d'Apple et ne touche jamais un simulateur allumé."
                )
                HStack(spacing: Space.m) {
                    PrimaryButton(title: "Actualiser", systemImage: "arrow.clockwise", tint: ModuleColor.maint) { model.load() }
                        .disabled(model.isLoading || model.isDeleting)
                        .opacity(model.isLoading || model.isDeleting ? 0.5 : 1)
                    if model.unavailableCount > 0 {
                        Button("Cocher les \(model.unavailableCount) \(pl(model.unavailableCount, "inutilisable"))") { model.selectUnavailable() }
                            .buttonStyle(LinkStyle())
                    }
                    Spacer()
                    if model.hasLoaded && model.xcodeInstalled {
                        Text("\(model.simulators.count) \(pl(model.simulators.count, "simulateur")) · \(model.runtimes.count) \(pl(model.runtimes.count, "runtime")) · \(humanSize(model.totalSize))")
                            .font(AppFont.secondary).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(Space.xl)
            .padding(.bottom, Space.s)

            content

            if model.hasLoaded && model.xcodeInstalled && !(model.simulators.isEmpty && model.runtimes.isEmpty) { footer }
        }
        .onAppear { if !model.hasLoaded { model.load() } }
        .sheet(isPresented: $confirming) { confirmation }
    }

    @ViewBuilder
    private var content: some View {
        if model.isDeleting {
            Spacer(); ProgressView("Suppression via Xcode…"); Spacer()
        } else if model.isLoading && !model.hasLoaded {
            Spacer(); ProgressView("Lecture des simulateurs…"); Spacer()
        } else if !model.xcodeInstalled {
            placeholder("hammer", model.statusMessage ?? "Xcode n'est pas installé sur ce Mac.")
        } else if model.simulators.isEmpty && model.runtimes.isEmpty {
            placeholder("checkmark.circle", "Aucun simulateur ni runtime.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if !model.runtimes.isEmpty {
                        section("Runtimes (systèmes de simulation)") {
                            ForEach(Array(model.runtimes.enumerated()), id: \.element.id) { idx, r in
                                if idx > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                                runtimeRow(r)
                            }
                        }
                    }
                    if !model.simulators.isEmpty {
                        section("Simulateurs") {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(model.simulators.enumerated()), id: \.element.id) { idx, s in
                                    if idx > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                                    simRow(s)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.xl).padding(.bottom, Space.l)
            }
        }
    }

    private func placeholder(_ icon: String, _ text: String) -> some View {
        VStack(spacing: Space.s) {
            Spacer()
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(Theme.faint)
            Text(text).font(AppFont.body).foregroundStyle(Theme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title.uppercased()).font(AppFont.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            VStack(spacing: 0) { content() }.card()
        }
    }

    private func runtimeRow(_ r: SimRuntimeInfo) -> some View {
        HStack(spacing: 11) {
            if r.deletable {
                CheckBox(label: "Sélectionner le runtime \(r.name)", on: model.selectedRuntimes.contains(r.identifier)) { model.toggle(r) }
            } else {
                Image(systemName: "lock.fill").font(AppFont.secondary).foregroundStyle(Theme.faint).frame(width: 18)
                    .help("Runtime protégé par le système")
            }
            ModuleIcon(symbol: "externaldrive.fill.badge.icloud", color: ModuleColor.maint, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name).font(AppFont.body.weight(.semibold))
                Text(r.devices == 0 ? "Aucun simulateur ne l'utilise" : "Utilisé par \(r.devices) \(pl(r.devices, "simulateur")), inutilisables sans lui")
                    .font(AppFont.caption).foregroundStyle(r.devices == 0 ? Theme.ok : Theme.warn)
            }
            Spacer(minLength: 8)
            if let d = lastUsed(r.last_used) {
                Text("utilisé \(d)").font(AppFont.caption).foregroundStyle(Theme.muted)
            }
            Text(humanSize(r.size_bytes)).font(AppFont.body.weight(.bold)).monospacedDigit()
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(r) }
    }

    private func simRow(_ s: SimDevice) -> some View {
        HStack(spacing: 11) {
            if s.isBooted {
                Image(systemName: "power.circle.fill").font(AppFont.body).foregroundStyle(Theme.ok).frame(width: 18)
                    .help("Allumé : éteignez-le pour pouvoir le supprimer")
            } else {
                CheckBox(label: "Sélectionner le simulateur \(s.name), \(s.runtime)", on: model.selectedSims.contains(s.udid)) { model.toggle(s) }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).font(AppFont.body.weight(.semibold))
                Text(s.runtime).font(AppFont.caption).foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 8)
            if s.isBooted {
                PillBadge(text: "Allumé", kind: .safe)
            } else if !s.available {
                PillBadge(text: "Inutilisable", kind: .review)
            }
            Text(lastUsed(s.last_used).map { "utilisé \($0)" } ?? "jamais utilisé")
                .font(AppFont.caption).foregroundStyle(Theme.muted)
            Text(humanSize(s.size_bytes)).font(AppFont.body.weight(.bold)).monospacedDigit()
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(s) }
    }

    private var footer: some View {
        HStack(spacing: Space.m) {
            Button("Tout décocher") { model.selectNone() }.buttonStyle(LinkStyle())
            if let s = model.lastSummary {
                Text(s).font(AppFont.secondary).foregroundStyle(model.lastNeedsAttention ? Theme.warn : Theme.muted)
            } else if let msg = model.statusMessage {
                Label(msg, systemImage: "exclamationmark.triangle.fill").font(AppFont.secondary).foregroundStyle(Theme.warn)
            }
            Spacer()
            if model.hasSelection {
                Text("Sélection : \(humanSize(model.selectedSize))").font(AppFont.secondary)
            }
            PrimaryButton(title: "Supprimer…", systemImage: "trash.slash", tint: Theme.danger) { confirming = true }
                .disabled(!model.hasSelection || model.isDeleting)
                .opacity(!model.hasSelection || model.isDeleting ? 0.5 : 1)
        }
        .padding(Space.l)
        .background(Theme.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    /// Confirmation : « Annuler » est l'action par défaut ; « Supprimer définitivement » n'a aucun raccourci.
    private var confirmation: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                Image(systemName: "exclamationmark.triangle.fill").font(AppFont.display).foregroundStyle(Theme.danger)
                Text("Supprimer définitivement ?").font(AppFont.emphasis.weight(.bold))
            }
            Text(summaryText).font(AppFont.body).fixedSize(horizontal: false, vertical: true)
            let orphaned = model.chosenRuntimes.reduce(0) { $0 + $1.devices }
            if orphaned > 0 {
                Text("\(orphaned) \(pl(orphaned, "simulateur")) \(pl(orphaned, "deviendra", "deviendront")) \(pl(orphaned, "inutilisable")) sans leur runtime.")
                    .font(AppFont.secondary).foregroundStyle(Theme.warn)
            }
            Text("Irréversible : les apps et données de test de ces simulateurs seront perdues. Xcode pourra retélécharger les runtimes.")
                .font(AppFont.secondary.weight(.semibold)).foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Annuler") { confirming = false }.keyboardShortcut(.defaultAction)
                Button(role: .destructive) {
                    confirming = false
                    model.deleteSelected()
                } label: { Text("Supprimer définitivement") }
                .tint(Theme.danger)
            }
        }
        .padding(Space.xl)
        .frame(width: 460)
        .onExitCommand { confirming = false }
    }

    private var summaryText: String {
        var parts: [String] = []
        if !model.chosenSims.isEmpty { parts.append("\(model.chosenSims.count) \(pl(model.chosenSims.count, "simulateur"))") }
        if !model.chosenRuntimes.isEmpty { parts.append("\(model.chosenRuntimes.count) \(pl(model.chosenRuntimes.count, "runtime")) (\(model.chosenRuntimes.map(\.name).joined(separator: ", ")))") }
        return parts.joined(separator: " et ") + " · \(humanSize(model.selectedSize)) seront supprimés via Xcode."
    }

    private static let iso = ISO8601DateFormatter()
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .full
        return f
    }()

    private func lastUsed(_ s: String?) -> String? {
        guard let s, let d = Self.iso.date(from: s) else { return nil }
        return Self.relative.localizedString(for: d, relativeTo: Date())
    }
}
