import SwiftUI

/// Présentation, analyse, bilan : les détails restent dans un gestionnaire distinct.
struct FilesOverviewView: View {
    @ObservedObject var app: AppState
    @ObservedObject private var analysis: FilesAnalysisModel
    @ObservedObject private var large: LargeFilesModel
    @ObservedObject private var duplicates: DuplicatesModel
    @AppStorage(FileStoragePreferences.Key.large) private var searchLarge = true
    @AppStorage(FileStoragePreferences.Key.duplicates) private var searchDuplicates = true
    @ScaledMetric private var heroSize = 44
    @ScaledMetric private var headlineSize = 26

    init(app: AppState) {
        self.app = app; analysis = app.filesAnalysis
        large = app.largeFiles; duplicates = app.duplicates
    }
    private var running: Bool { large.stage == .scanning || duplicates.stage == .scanning }
    private var anyResults: Bool { large.stage == .results || duplicates.stage == .results }
    private var showLarge: Bool { !analysis.hasStarted || analysis.requestedLarge }
    private var showDuplicates: Bool { !analysis.hasStarted || analysis.requestedDuplicates }
    private var count: Int {
        let largePaths = showLarge && large.stage == .results ? large.visible.map(\.path) : []
        let dupPaths = showDuplicates && duplicates.stage == .results ? duplicates.groups.flatMap(\.files).map(\.path) : []
        return Set(largePaths + dupPaths).count
    }

    var body: some View {
        ZStack {
            CategoryBackground(section: .files)
            if analysis.choosingLocation { introduction }
            else if running { progress }
            else if analysis.hasStarted || analysis.browsing || anyResults { summary }
            else { introduction }
        }.foregroundStyle(.white).disabled(large.isTrashing || duplicates.isTrashing)
            .onChange(of: analysis.searchRoot) { _ in
                large.clearResults(); duplicates.clearResults()
            }
    }

    private var introduction: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    HStack(spacing: 48) {
                        FilesArtwork().frame(width: geometry.size.width < 800 ? 220 : 280)
                        VStack(alignment: .leading, spacing: 22) {
                            Text("Mes fichiers").font(.system(size: heroSize)).accessibilityAddTraits(.isHeader)
                            Text("Passez en revue vos fichiers et faites du tri, à votre rythme.")
                                .font(.system(size: 18)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            VStack(alignment: .leading, spacing: 20) {
                                OverviewFeatureRow(symbol: "doc.text.magnifyingglass", title: "Fichiers volumineux", tint: FilesStyle.accent.shade(0.65))
                                OverviewFeatureRow(symbol: "doc.on.doc", title: "Doublons identiques", tint: FilesStyle.accent.shade(0.65))
                            }.padding(.top, 10)
                            locationMenu
                            if let error = analysis.locationError {
                                Label(error, systemImage: "exclamationmark.triangle").font(AppFont.secondary)
                            }
                        }.frame(maxWidth: 450, alignment: .leading)
                    }.padding(36).frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
            OverviewActionFooter(caption: "Analyse seule. Vous choisissez ensuite ce que vous souhaitez garder.",
                                 message: !searchLarge && !searchDuplicates ? "Activez une recherche dans Réglages → Fichiers et disque." : nil) {
                Button("Analyser") { analyze() }
                    .buttonStyle(CircularOverviewActionStyle(tint: FilesStyle.accent))
                    .disabled(!searchLarge && !searchDuplicates)
                    .accessibilityLabel("Analyser les fichiers du dossier choisi")
            } secondary: {
                Button("Examiner les catégories sans analyser") { analysis.choosingLocation = false; analysis.browsing = true }
                    .buttonStyle(SecondaryActionButtonStyle()).font(AppFont.secondary)
            }
        }
    }

    private var locationMenu: some View {
        FileSearchLocationMenu(model: analysis)
            .frame(height: 44).padding(.horizontal, 12)
            .frame(maxWidth: 290)
            .background(.white.opacity(0.17), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.2)))
    }

    private var progress: some View {
        AnalysisProgressView(title: "Recherche de vos fichiers…", detail: analysis.searchRoot.path,
                             symbol: "folder.fill", color: FilesStyle.accent, cancelTitle: "Arrêter les recherches",
                             cancel: { analysis.cancel(large: large, duplicates: duplicates) }) {
            if large.stage == .scanning { Text("Gros fichiers : \(large.liveEntries.formatted()) entrées lues") }
            if duplicates.stage == .scanning { Text("Doublons : \(duplicates.liveEntries.formatted()) entrées lues") }
        }
    }

    private var summary: some View {
        VStack(spacing: 0) {
            ScreenToolbar(title: "Mes fichiers") {
                Button { analysis.choosingLocation = true } label: { Label("Recommencer", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.plain)
            } trailing: { EmptyView() }.padding(.horizontal, 30).padding(.top, 20)
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 24) {
                        FilesArtwork().frame(width: 160, height: 155)
                        VStack(spacing: 8) {
                            Text(anyResults ? "\(count) \(pl(count, "fichier")) à examiner" : "Vos fichiers, à examiner")
                                .font(.system(size: headlineSize, weight: .semibold)).accessibilityAddTraits(.isHeader)
                            Text("Examinez les résultats avant de choisir les éléments à retirer.")
                                .font(AppFont.body).foregroundStyle(.white.opacity(0.8))
                        }.multilineTextAlignment(.center)
                        Button("Examiner tous les fichiers") { app.module = showDuplicates && (!showLarge || large.visible.isEmpty) && !duplicates.groups.isEmpty ? .duplicates : .largeFiles }
                            .buttonStyle(SecondaryActionButtonStyle()).controlSize(.large)
                        HStack(alignment: .top, spacing: 18) {
                            resultCard(duplicates: true).frame(maxWidth: .infinity)
                            resultCard(duplicates: false).frame(maxWidth: .infinity)
                        }.padding(.top, 16)
                        InterfaceHelp(title: "À propos des résultats", message: "Un fichier peut apparaître dans les deux catégories ; leurs volumes ne s’additionnent pas. Les doublons sont identiques par contenu. Une copie reste conservée. Les éléments choisis passent toujours par la corbeille.")
                    }.padding(30).frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
        }
    }

    private func resultCard(duplicates isDuplicates: Bool) -> some View {
        let included = isDuplicates ? showDuplicates : showLarge
        let ready = isDuplicates ? duplicates.stage == .results : large.stage == .results
        let message = isDuplicates ? duplicates.statusMessage : large.statusMessage
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(isDuplicates ? "Doublons" : "Fichiers volumineux").font(AppFont.section.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                Image(systemName: isDuplicates ? "doc.on.doc" : "doc.text.magnifyingglass").font(.title2).accessibilityHidden(true)
            }
            if included && ready {
                Text(isDuplicates ? "\(duplicates.groups.count) \(pl(duplicates.groups.count, "groupe")) · jusqu’à \(humanSize(duplicates.reclaimable)) de copies" : "\(large.visible.count) \(pl(large.visible.count, "fichier")) · \(humanSize(large.visibleSize))")
                    .font(AppFont.body).monospacedDigit()
            } else {
                Text(included ? "Recherche à lancer" : "Non inclus dans cette analyse").font(AppFont.body)
            }
            if let message, included { Text(message).font(AppFont.secondary) }
            Spacer(minLength: 12)
            HStack {
                Text(isDuplicates ? "Une copie conservée par groupe." : "Un gros fichier peut encore vous être utile.")
                    .font(AppFont.secondary).foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 8)
                Button("Examiner") { app.module = isDuplicates ? .duplicates : .largeFiles }
                    .buttonStyle(SecondaryActionButtonStyle()).accessibilityLabel(isDuplicates ? "Examiner les doublons" : "Examiner les gros fichiers")
            }
        }.padding(22).frame(minHeight: 180, alignment: .topLeading)
            .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.16)))
    }
    private func analyze() { analysis.analyze(large: large, duplicates: duplicates) }
}

enum FilesStyle {
    static let accent = Color(hex: "159DAB")
    static let ink = Color(hex: "20242C")
    static let secondary = Color(hex: "666C76")
    static let selection = Color(hex: "E4F3F4")
}

struct FilesArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: geometry.size.width * 0.24)
                    .fill(LinearGradient(colors: [FilesStyle.accent.shade(0.2), Color(hex: "064B55")], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: geometry.size.width * 0.24).strokeBorder(.white.opacity(0.4)))
                    .rotationEffect(.degrees(-8))
                Image(systemName: "folder.fill").resizable().scaledToFit().padding(geometry.size.width * 0.24)
                    .foregroundStyle(LinearGradient(colors: [.white, Color(hex: "A2E5E9")], startPoint: .top, endPoint: .bottom))
            }.padding(12).frame(maxHeight: .infinity)
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
}
