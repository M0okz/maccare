import SwiftUI

struct DuplicatesView: View {
    @ObservedObject var model: DuplicatesModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.l) {
                ScreenHeader(
                    title: "Doublons",
                    subtitle: "Comparez les copies identiques. Une copie de chaque groupe est toujours conservée."
                )
                HStack(spacing: Space.m) {
                    PrimaryButton(title: model.stage == .results ? "Relancer" : "Rechercher",
                                  systemImage: "doc.on.doc", tint: ModuleColor.space) { model.scan() }
                        .disabled(model.stage == .scanning || model.isTrashing)
                        .opacity(model.stage == .scanning || model.isTrashing ? 0.5 : 1)
                    Spacer()
                    if model.stage == .results && !model.groups.isEmpty {
                        Text("\(model.groups.count) \(pl(model.groups.count, "groupe")) · jusqu'à \(humanSize(model.reclaimable)) récupérables")
                            .font(AppFont.secondary).foregroundStyle(Theme.muted)
                            .help("Estimation : une copie faite dans le Finder partage souvent son espace avec l'original (clone APFS) et n'en libère alors presque pas.")
                    }
                }
            }
            .padding(Space.xl)
            .padding(.bottom, Space.s)

            content

            if model.stage == .results && !model.groups.isEmpty { footer }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .scanning: scanning
        case .idle:
            placeholder(icon: "doc.on.doc", text: model.statusMessage ?? "Lancez une recherche des doublons de votre dossier personnel.")
        case .results:
            if model.groups.isEmpty {
                placeholder(icon: "checkmark.circle", text: model.statusMessage ?? "Aucun doublon trouvé.")
            } else {
                list
            }
        }
    }

    private var scanning: some View {
        AnalysisProgressView(title: "Comparaison des doublons…", detail: "Dossier personnel · aucune suppression pendant la recherche.", symbol: "doc.on.doc", color: ModuleColor.space, cancelTitle: "Arrêter la recherche", cancel: { model.cancel() }) {
            Text("\(model.liveEntries.formatted()) entrées lues · \(humanSize(model.liveBytes))")
        }
    }

    private func placeholder(icon: String, text: String) -> some View {
        VStack(spacing: Space.s) {
            Spacer()
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(Theme.faint)
            Text(text).font(AppFont.body).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(Space.xl)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                ForEach(model.groups) { groupCard($0) }
            }
            .padding(.horizontal, Space.xl).padding(.bottom, Space.l)
        }
    }

    private func groupCard(_ g: DupGroup) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                ModuleIcon(symbol: "doc.on.doc.fill", color: ModuleColor.space, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(g.files.first?.url.lastPathComponent ?? "").font(AppFont.body.weight(.semibold)).lineLimit(1)
                    Text("\(g.files.count) copies identiques · \(humanSize(g.files.first?.size_bytes ?? 0)) chacune")
                        .font(AppFont.caption).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Button("Cocher les copies") { model.selectCopies(in: g) }.buttonStyle(LinkStyle())
                Text("jusqu'à \(humanSize(g.reclaimable))")
                    .font(AppFont.body.weight(.bold)).monospacedDigit()
                    .frame(minWidth: 72, alignment: .trailing)
                    .help("Espace libéré au plus : rien si les copies sont des clones APFS.")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            ForEach(g.files) { f in
                Rectangle().fill(Theme.hairline).frame(height: 1)
                row(f, in: g)
            }
        }
        .card()
    }

    private func row(_ f: DupFile, in g: DupGroup) -> some View {
        let kept = model.isKept(f, in: g)
        return HStack(spacing: 11) {
            if kept {
                Image(systemName: "lock.fill").font(AppFont.secondary).foregroundStyle(Theme.ok)
                    .frame(width: 18)
                    .help("Exemplaire conservé : jamais mis à la corbeille")
            } else {
                CheckBox(label: "Sélectionner la copie \(f.path)", on: model.selection.contains(f.path)) { model.toggle(f, in: g) }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(displayPath(f)).font(AppFont.secondary).lineLimit(1).truncationMode(.middle)
                Text("modifié \(Self.relative.localizedString(for: f.modifiedDate, relativeTo: Date()))")
                    .font(AppFont.caption).foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 8)
            if kept {
                PillBadge(text: "Conservé", kind: .safe)
            } else {
                Button("Garder celui-ci") { model.keep(f, in: g) }.buttonStyle(LinkStyle())
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([f.url])
            } label: {
                Image(systemName: "magnifyingglass.circle").font(AppFont.body)
            }
            .buttonStyle(.plain).foregroundStyle(Theme.muted)
            .help("Afficher dans le Finder")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .padding(.leading, 30)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(f, in: g) }
        .contextMenu {
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([f.url]) }
            Button("Ouvrir") { NSWorkspace.shared.open(f.url) }
        }
    }

    private var footer: some View {
        AdaptiveActionRow {
            VStack(alignment: .leading, spacing: 8) {
                Button("Cocher toutes les copies") { model.selectAllCopies() }.buttonStyle(LinkStyle())
                Button("Tout décocher") { model.selectNone() }.buttonStyle(LinkStyle())
                if let r = model.lastReport {
                    Text(r.summary).font(AppFont.secondary).foregroundStyle(r.needsAttention ? Theme.warn : Theme.muted)
                } else if let msg = model.statusMessage {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(AppFont.secondary).foregroundStyle(Theme.warn)
                }
            }
        } actions: {
            HStack(spacing: Space.m) {
                if !model.selectedFiles.isEmpty {
                    Text("Sélection : \(humanSize(model.selectedSize))").font(AppFont.secondary)
                }
                PrimaryButton(title: model.isTrashing ? "Vérification…" : "Déplacer vers la corbeille",
                              systemImage: "trash", tint: ModuleColor.space) { model.trashSelected() }
                    .disabled(model.selectedFiles.isEmpty || model.isTrashing)
                    .opacity(model.selectedFiles.isEmpty || model.isTrashing ? 0.5 : 1)
                    .help("Toujours vers la corbeille. Chaque copie est d'abord comparée à l'exemplaire conservé.")
            }
        }
        .padding(Space.l)
        .background(Theme.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func displayPath(_ f: DupFile) -> String {
        let home = NSHomeDirectory()
        return f.path.hasPrefix(home) ? "~" + f.path.dropFirst(home.count) : f.path
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .full
        return f
    }()
}
