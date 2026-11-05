import SwiftUI
import AppKit
import Quartz
import ImageIO

struct FilesManagerView: View {
    @ObservedObject var app: AppState
    @ObservedObject private var large: LargeFilesModel
    @ObservedObject private var duplicates: DuplicatesModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let category: FileManagerCategory
    @State private var query = ""
    @State private var sort = FileManagerSort.size
    @State private var groupID: String?
    @State private var inspectedCopy: String?
    @State private var previewLarge: LargeFile?

    init(app: AppState, category: FileManagerCategory) {
        self.app = app; self.large = app.largeFiles; self.duplicates = app.duplicates; self.category = category
    }
    private var busy: Bool { large.isTrashing || duplicates.isTrashing || large.stage == .scanning || duplicates.stage == .scanning }
    private var running: Bool { category == .large ? large.stage == .scanning : duplicates.stage == .scanning }
    private var groups: [DupGroup] { FileManagerPresentation.groups(duplicates.groups, query: query, sort: sort) }
    private var activeGroup: DupGroup? { groups.first { $0.id == groupID } ?? groups.first }
    private var files: [LargeFile] { FileManagerPresentation.files(large.visible, query: query, sort: sort, lastOpened: large.lastOpened) }
    private var chosenCount: Int { category == .large ? large.selectedFiles.count : duplicates.selectedFiles.count }
    private var chosenSize: UInt64 { category == .large ? large.selectedSize : duplicates.selectedSize }
    private var message: String? { category == .large ? (large.lastReport?.summary ?? large.statusMessage) : (duplicates.lastReport?.summary ?? duplicates.statusMessage) }

    var body: some View {
        VStack(spacing: 0) {
            ScreenToolbar(title: "Gestionnaire de fichiers") {
                Button { app.module = .filesOverview } label: { Label("Retour", systemImage: "chevron.left") }.buttonStyle(ToolbarActionButtonStyle())
            } trailing: { EmptyView() }.padding(.horizontal, 24).frame(height: 56)
            Divider()
            controls.padding(.horizontal, 20).padding(.vertical, 14)
            Divider()
            if running {
                AnalysisProgressView(title: "Recherche de vos fichiers…", detail: app.filesAnalysis.searchRoot.path,
                                     symbol: "folder.fill", color: FilesStyle.accent, cancel: { cancel() }) {
                    Text("\((category == .large ? large.liveEntries : duplicates.liveEntries).formatted()) entrées lues")
                }.foregroundStyle(.white).background(Color(hex: "07575D"))
            } else if category == .duplicates { duplicateBrowser }
            else { largeBrowser }
            Divider()
            footer
        }
        .modifier(ManagerPanelStyle(accent: FilesStyle.accent, background: Color(hex: "063D43")))
        .sheet(item: $previewLarge) { file in
            VStack(spacing: 16) {
                FileInspectionView(url: file.url, size: file.size_bytes, modified: file.modifiedDate)
                Button("Fermer") { previewLarge = nil }.keyboardShortcut(.cancelAction)
            }.padding(24).frame(width: 660, height: 540)
                .background(Color.white).foregroundStyle(FilesStyle.ink).environment(\.colorScheme, .light)
        }
        // Les feuilles gardent leur présentation native ; aucun mouvement ajouté par-dessus.
        .transaction { transaction in
            if reduceMotion { transaction.disablesAnimations = true }
        }
        .onChange(of: query) { _ in
            if category == .large { large.selection.formIntersection(Set(files.map(\.path))) }
            else { duplicates.retainSelection(in: Set(groups.flatMap(\.files).map(\.path))) }
        }
        .onChange(of: activeGroup?.id) { _ in inspectedCopy = nil }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Picker("Catégorie", selection: Binding(get: { category }, set: { app.module = $0 == .large ? .largeFiles : .duplicates })) {
                    ForEach(FileManagerCategory.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).frame(width: 280).disabled(busy)
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").accessibilityHidden(true)
                    TextField("Rechercher", text: $query).textFieldStyle(.plain).accessibilityLabel("Rechercher dans les résultats")
                }.padding(8).background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)).frame(maxWidth: 210)
                Picker("Trier par", selection: $sort) {
                    ForEach(FileManagerSort.allCases.filter { category == .large || $0 != .lastOpened }) { Text($0.title).tag($0) }
                }.frame(width: 220)
            }
            HStack(spacing: 12) {
                if category == .large {
                    Text("Taille minimale").font(AppFont.secondary)
                    Picker("Taille minimale", selection: $large.minSize) {
                        ForEach(LargeFilesModel.MinSize.allCases) { Text("≥ \($0.title)").tag($0) }
                    }.labelsHidden().frame(width: 110).accessibilityLabel("Taille minimale")
                    Picker("Dernière ouverture", selection: $large.age) {
                        ForEach(LargeFilesModel.Age.allCases) { Text($0.title).tag($0) }
                    }.frame(maxWidth: 235)
                } else {
                    Menu("Sélectionner : \(chosenCount == 0 ? "aucun" : "\(chosenCount) \(pl(chosenCount, "copie"))")") {
                        Button("Cocher les copies affichées") { groups.forEach { duplicates.selectCopies(in: $0) } }
                        Button("Tout décocher") { duplicates.selectNone() }
                    }.frame(maxWidth: 230)
                }
                Spacer(minLength: 8)
                Button("Actualiser", systemImage: "arrow.clockwise") { scan() }
            }.disabled(busy)
        }
    }

    private var duplicateBrowser: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Doublons détectés").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                Text("Choisissez un groupe, puis comparez ses copies. Une copie reste toujours conservée.")
                    .font(AppFont.secondary).foregroundStyle(FilesStyle.secondary)
                if groups.isEmpty { emptyState }
                else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(groups) { group in
                                Button { groupID = group.id; inspectedCopy = nil } label: {
                                    HStack(spacing: 10) {
                                        FileThumbnail(url: URL(fileURLWithPath: group.files.first?.path ?? "")).frame(width: 42, height: 42)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(URL(fileURLWithPath: group.files.first?.path ?? "").lastPathComponent).font(AppFont.body.weight(.semibold)).lineLimit(1)
                                            Text("\(humanSize(group.reclaimable)) de copies").font(AppFont.secondary).foregroundStyle(FilesStyle.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Text("\(group.files.count)").font(AppFont.secondary.weight(.semibold))
                                            .padding(5).background(.white, in: RoundedRectangle(cornerRadius: 5))
                                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(activeGroup?.id == group.id ? FilesStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain).accessibilityLabel("\(group.files.count) copies de \(URL(fileURLWithPath: group.files.first?.path ?? "").lastPathComponent)")
                                    .accessibilityAddTraits(activeGroup?.id == group.id ? .isSelected : [])
                            }
                        }
                    }
                }
            }.padding(16).frame(width: 258).frame(maxHeight: .infinity, alignment: .topLeading)
            Divider()
            if let group = activeGroup { duplicateDetail(group) }
            else { emptyDetail.frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
    }

    private func duplicateDetail(_ group: DupGroup) -> some View {
        let file = group.files.first { $0.path == inspectedCopy } ?? group.files.first { duplicates.isKept($0, in: group) } ?? group.files[0]
        return HStack(alignment: .top, spacing: 16) {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(group.files) { copy in
                        VStack(spacing: 6) {
                            Button { inspectedCopy = copy.path } label: {
                                FileThumbnail(url: copy.url).frame(width: 64, height: 64).padding(5)
                                    .background(file.path == copy.path ? FilesStyle.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(file.path == copy.path ? FilesStyle.accent : .clear, lineWidth: 2))
                            }.buttonStyle(.plain).accessibilityLabel("Examiner \(copy.path)")
                                .accessibilityAddTraits(file.path == copy.path ? .isSelected : [])
                            if duplicates.isKept(copy, in: group) {
                                Label("Conservé", systemImage: "checkmark.shield.fill").font(.caption).foregroundStyle(Color(hex: "15756B"))
                            } else {
                                Toggle("Retirer", isOn: Binding(get: { duplicates.selection.contains(copy.path) }, set: { _ in duplicates.toggle(copy, in: group) }))
                                    .toggleStyle(.checkbox).font(.caption).disabled(busy).accessibilityLabel("Retirer la copie \(copy.path)")
                            }
                        }
                    }
                }.padding(4)
            }.frame(width: 94)
            VStack(alignment: .leading, spacing: 12) {
                FileInspectionView(url: file.url, size: file.size_bytes, modified: file.modifiedDate)
                Button(duplicates.isKept(file, in: group) ? "Cette copie est conservée" : "Conserver cette copie") { duplicates.keep(file, in: group) }
                    .disabled(busy || duplicates.isKept(file, in: group))
                    .help("La copie conservée ne peut pas être cochée pour la corbeille.")
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(20)
    }

    private var largeBrowser: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fichiers volumineux").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                    Text("Ouvrez un aperçu pour examiner un fichier. Cochez uniquement les éléments à retirer.")
                        .font(AppFont.secondary).foregroundStyle(FilesStyle.secondary)
                }
                Spacer()
                Button("Tout décocher") { large.selectNone() }.disabled(busy || large.selectedFiles.isEmpty)
            }.padding(.horizontal, 24).padding(.top, 20)
            if files.isEmpty { emptyState.frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(files) { file in
                            HStack(spacing: 14) {
                                Toggle("Retirer", isOn: Binding(get: { large.selection.contains(file.path) }, set: { _ in large.toggle(file) }))
                                    .labelsHidden().toggleStyle(.checkbox).disabled(busy).accessibilityLabel("Retirer \(file.path)")
                                Button { previewLarge = file } label: {
                                    HStack(spacing: 14) {
                                        FileThumbnail(url: file.url).frame(width: 44, height: 44)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(file.url.lastPathComponent).font(AppFont.body.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                                            Text(file.url.deletingLastPathComponent().path).font(AppFont.secondary).foregroundStyle(FilesStyle.secondary).lineLimit(1).truncationMode(.middle)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                        Text(file.modifiedDate, format: .dateTime.day().month(.abbreviated).year()).font(AppFont.secondary).foregroundStyle(FilesStyle.secondary).frame(width: 105, alignment: .trailing)
                                        Text(humanSize(file.size_bytes)).font(AppFont.body).monospacedDigit().frame(width: 85, alignment: .trailing)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("Examiner \(file.url.lastPathComponent), \(humanSize(file.size_bytes))")
                            }.padding(14).background(large.selection.contains(file.path) ? FilesStyle.selection : Color.black.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                                .contextMenu {
                                    Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                                    Button("Ouvrir") { NSWorkspace.shared.open(file.url) }
                                }
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 16)
                }
            }
        }
    }

    private var footer: some View {
        AdaptiveActionRow {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(category.title) : \(chosenCount) \(pl(chosenCount, "sélectionné")) · \(humanSize(chosenSize))").font(AppFont.body.weight(.semibold))
                Text(message ?? "Les éléments choisis seront déplacés vers la corbeille.")
                    .font(AppFont.secondary).foregroundStyle(FilesStyle.secondary)
            }
        } actions: {
            Button { category == .large ? large.trashSelected() : duplicates.trashSelected() } label: {
                Label("Déplacer vers la corbeille", systemImage: "trash").padding(.horizontal, 10).padding(.vertical, 6)
            }.buttonStyle(.borderedProminent).disabled(chosenCount == 0 || busy)
        }.padding(18).background(Color(hex: "F5F6F8"))
    }
    private var emptyState: some View {
        VStack(spacing: 14) {
            if category == .large && query.isEmpty && !large.files.isEmpty {
                Text("Aucun fichier ne correspond aux filtres.").foregroundStyle(FilesStyle.secondary)
                Button("Réinitialiser les filtres") { large.minSize = .mb50; large.age = .any }.disabled(busy)
            } else {
                Text(query.isEmpty ? (message ?? "Aucun résultat à afficher.") : "Aucun résultat pour cette recherche.")
                    .foregroundStyle(FilesStyle.secondary).multilineTextAlignment(.center)
                if query.isEmpty { Button("Lancer la recherche") { scan() }.disabled(busy) }
            }
        }.padding(20)
    }
    private var emptyDetail: some View { Label("Choisissez un groupe à examiner.", systemImage: "doc.on.doc").foregroundStyle(FilesStyle.secondary) }
    private func scan() {
        if category == .large { large.scan(at: app.filesAnalysis.searchRoot) }
        else { duplicates.scan(at: app.filesAnalysis.searchRoot) }
    }
    private func cancel() { if category == .large { large.cancel() } else { duplicates.cancel() } }
}

struct FileInspectionView: View {
    let url: URL
    let size: UInt64
    let modified: Date
    private var values: URLResourceValues? { try? url.resourceValues(forKeys: [.creationDateKey, .localizedTypeDescriptionKey]) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NativeFilePreview(url: url).frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 150)
                .accessibilityLabel("Aperçu de \(url.lastPathComponent)")
            Text(url.lastPathComponent).font(AppFont.emphasis).lineLimit(2).accessibilityAddTraits(.isHeader)
            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                Label(url.deletingLastPathComponent().path, systemImage: "folder").lineLimit(2).truncationMode(.middle)
            }.buttonStyle(.plain).font(AppFont.secondary).foregroundStyle(FilesStyle.secondary).help("Afficher dans le Finder")
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
                GridRow { Text("Modifié"); Text(modified, format: .dateTime.day().month(.wide).year()) }
                if let created = values?.creationDate { GridRow { Text("Créé"); Text(created, format: .dateTime.day().month(.wide).year()) } }
                GridRow { Text("Taille"); Text(humanSize(size)).monospacedDigit() }
                GridRow { Text("Type"); Text(values?.localizedTypeDescription ?? url.pathExtension.uppercased()) }
            }.font(AppFont.secondary)
        }
    }
}

/// Quick Look charge l’aperçu ; les vidéos ne démarrent pas automatiquement.
struct NativeFilePreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = false; view.shouldCloseWithWindow = true
        view.appearance = NSAppearance(named: .aqua)
        view.previewItem = url as NSURL
        return view
    }
    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) != url as NSURL { view.previewItem = url as NSURL }
    }
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.close() }
}

struct FileThumbnail: View {
    let url: URL
    @State private var image: CGImage?
    var body: some View {
        Group {
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
            else { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit() }
        }.accessibilityHidden(true)
            .task(id: url) {
                image = nil
                let result = await Task.detached(priority: .utility) { () -> CGImage? in
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                    return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 128, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
                }.value
                if !Task.isCancelled { image = result }
            }
    }
}

enum FileManagerCategory: String, CaseIterable, Identifiable {
    case large, duplicates
    var id: String { rawValue }
    var title: String { self == .large ? "Gros fichiers" : "Doublons" }
}
enum FileManagerSort: String, CaseIterable, Identifiable {
    case size, name, date, lastOpened
    var id: String { rawValue }
    var title: String { switch self { case .size: return "Taille"; case .name: return "Nom"; case .date: return "Modification"; case .lastOpened: return "Dernière ouverture" } }
}
enum FileManagerPresentation {
    static func files(_ files: [LargeFile], query: String, sort: FileManagerSort, lastOpened: [String: Date] = [:]) -> [LargeFile] {
        files.filter { query.isEmpty || $0.path.localizedCaseInsensitiveContains(query) }.sorted {
            switch sort {
            case .size: return $0.size_bytes == $1.size_bytes ? $0.path < $1.path : $0.size_bytes > $1.size_bytes
            case .name: return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            case .date: return $0.modified == $1.modified ? $0.path < $1.path : $0.modified < $1.modified
            case .lastOpened: return (lastOpened[$0.path] ?? $0.modifiedDate) < (lastOpened[$1.path] ?? $1.modifiedDate)
            }
        }
    }
    static func groups(_ groups: [DupGroup], query: String, sort: FileManagerSort) -> [DupGroup] {
        groups.filter { query.isEmpty || $0.files.contains { $0.path.localizedCaseInsensitiveContains(query) } }.sorted {
            switch sort {
            case .size: return $0.reclaimable == $1.reclaimable ? $0.id < $1.id : $0.reclaimable > $1.reclaimable
            case .name: return ($0.files.first?.url.lastPathComponent ?? "").localizedStandardCompare($1.files.first?.url.lastPathComponent ?? "") == .orderedAscending
            case .date, .lastOpened: return ($0.files.first?.modified ?? 0) < ($1.files.first?.modified ?? 0)
            }
        }
    }
}
