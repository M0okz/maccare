import SwiftUI

struct LargeFilesView: View {
    @ObservedObject var model: LargeFilesModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.l) {
                ScreenHeader(
                    title: "Gros fichiers",
                    subtitle: "Retrouvez les fichiers volumineux de votre dossier personnel. Vous choisissez ce que vous gardez."
                )
                controls
            }
            .padding(Space.xl)
            .padding(.bottom, Space.s)

            content

            if model.stage == .results && !model.files.isEmpty { footer }
        }
        .onAppear { if model.stage == .idle { model.applyDefaultFilters() } }
    }

    // MARK: Contrôles

    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                PrimaryButton(title: model.stage == .results ? "Relancer" : "Rechercher",
                              systemImage: "magnifyingglass", tint: ModuleColor.space) { model.scan() }
                    .fixedSize()
                    .disabled(model.stage == .scanning || model.isTrashing)
                    .opacity(model.stage == .scanning || model.isTrashing ? 0.5 : 1)
                Spacer()
                if model.stage == .results {
                    Picker("Tri", selection: $model.sort) {
                        ForEach(LargeFilesModel.Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu).fixedSize()
                }
            }
            if model.stage == .results {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.m) { sizeFilter; ageFilter }
                    VStack(alignment: .leading, spacing: Space.m) { sizeFilter; ageFilter }
                }
            }
        }
        .labelsHidden()
    }

    private var sizeFilter: some View {
        Picker("Taille", selection: $model.minSize) {
            ForEach(LargeFilesModel.MinSize.allCases) { Text("≥ \($0.title)").tag($0) }
        }
        .pickerStyle(.segmented).fixedSize()
        .accessibilityLabel("Taille minimale")
    }

    private var ageFilter: some View {
        Picker("Ouvert", selection: $model.age) {
            ForEach(LargeFilesModel.Age.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented).fixedSize()
        .accessibilityLabel("Dernière ouverture")
    }

    // MARK: Contenu

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .scanning: scanning
        case .idle: placeholder(icon: "doc.richtext", text: model.statusMessage ?? "Lancez une recherche des gros fichiers de votre dossier personnel.")
        case .results:
            if model.visible.isEmpty {
                placeholder(icon: "checkmark.circle",
                            text: model.files.isEmpty ? "Aucun fichier de plus de 50 Mo trouvé." : "Aucun fichier ne correspond à ces filtres.")
            } else {
                list
            }
        }
    }

    private var scanning: some View {
        AnalysisProgressView(title: "Recherche des gros fichiers…", detail: "Dossier personnel · aucune suppression pendant la recherche.", symbol: "doc.richtext", color: ModuleColor.space, cancelTitle: "Arrêter la recherche", cancel: { model.cancel() }) {
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
            LazyVStack(spacing: 0) {
                ForEach(Array(model.visible.enumerated()), id: \.element.id) { idx, file in
                    if idx > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    row(file)
                }
            }
            .card()
            .padding(.horizontal, Space.xl).padding(.bottom, Space.l)
        }
    }

    private func row(_ f: LargeFile) -> some View {
        HStack(spacing: 11) {
            CheckBox(label: "Sélectionner \(f.path)", on: model.selection.contains(f.path)) { model.toggle(f) }
            ModuleIcon(symbol: symbol(for: f), color: ModuleColor.space, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(f.url.lastPathComponent).font(AppFont.body.weight(.semibold)).lineLimit(1)
                Text(displayPath(f)).font(AppFont.caption).foregroundStyle(Theme.faint)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(ageText(f)).font(AppFont.caption).foregroundStyle(Theme.muted)
            Text(humanSize(f.size_bytes))
                .font(AppFont.body.weight(.bold)).monospacedDigit()
                .frame(minWidth: 72, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([f.url])
            } label: {
                Image(systemName: "magnifyingglass.circle").font(AppFont.body)
            }
            .buttonStyle(.plain).foregroundStyle(Theme.muted)
            .help("Afficher dans le Finder")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(f) }
        .contextMenu {
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([f.url]) }
            Button("Ouvrir") { NSWorkspace.shared.open(f.url) }
        }
    }

    // MARK: Pied

    private var footer: some View {
        AdaptiveActionRow {
            VStack(alignment: .leading, spacing: 8) {
                Button("Tout décocher") { model.selectNone() }.buttonStyle(LinkStyle())
                if let r = model.lastReport {
                    Text(r.summary).font(AppFont.secondary).foregroundStyle(r.needsAttention ? Theme.warn : Theme.muted)
                } else if let msg = model.statusMessage {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(AppFont.secondary).foregroundStyle(Theme.warn)
                } else {
                    Text("\(model.visible.count) \(pl(model.visible.count, "fichier")) · \(humanSize(model.visibleSize))")
                        .font(AppFont.secondary).foregroundStyle(Theme.muted)
                }
            }
        } actions: {
            HStack(spacing: Space.m) {
                if !model.selectedFiles.isEmpty {
                    Text("Sélection : \(humanSize(model.selectedSize))").font(AppFont.secondary)
                }
                PrimaryButton(title: "Déplacer vers la corbeille", systemImage: "trash", tint: ModuleColor.space) {
                    model.trashSelected()
                }
                .disabled(model.selectedFiles.isEmpty || model.isTrashing)
                .opacity(model.selectedFiles.isEmpty || model.isTrashing ? 0.5 : 1)
                .help("Toujours vers la corbeille, récupérable depuis le Finder.")
            }
        }
        .padding(Space.l)
        .background(Theme.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    // MARK: Présentation

    private func displayPath(_ f: LargeFile) -> String {
        let home = NSHomeDirectory()
        let dir = (f.path as NSString).deletingLastPathComponent
        return dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .full
        return f
    }()

    private func ageText(_ f: LargeFile) -> String {
        if let d = model.lastOpened[f.path] {
            return "ouvert \(Self.relative.localizedString(for: d, relativeTo: Date()))"
        }
        return "modifié \(Self.relative.localizedString(for: f.modifiedDate, relativeTo: Date()))"
    }

    private func symbol(for f: LargeFile) -> String {
        switch f.url.pathExtension.lowercased() {
        case "mov", "mp4", "m4v", "mkv", "avi": return "film.fill"
        case "dmg", "iso", "img", "pkg": return "opticaldiscdrive.fill"
        case "zip", "tar", "gz", "tgz", "7z", "rar", "xz": return "archivebox.fill"
        case "jpg", "jpeg", "png", "heic", "tif", "tiff", "psd", "raw": return "photo.fill"
        case "mp3", "wav", "aiff", "flac", "m4a": return "music.note"
        case "pdf": return "doc.richtext.fill"
        default: return "doc.fill"
        }
    }
}
