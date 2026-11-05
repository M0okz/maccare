import SwiftUI

struct CleaningOverviewView: View {
    @ObservedObject var app: AppState
    @ObservedObject private var smart: SmartScanModel
    @ObservedObject private var trash: TrashModel
    @AppStorage(DeveloperTools.key) private var developerTools = DeveloperTools.defaultValue
    @AppStorage("cleaningProfile") private var profile = CleaningProfile.recommended.rawValue
    private var browsingTools: Bool { app.cleaningToolsVisible }

    init(app: AppState) {
        self.app = app
        self.smart = app.smartScan
        self.trash = app.trash
    }

    private var hasResults: Bool { smart.stage == .results || smart.stage == .cleaning }
    private var result: CleaningSummary {
        CleaningSummary(isComplete: smart.isComplete, wasCancelled: smart.wasCancelled,
                        isCleaning: smart.stage == .cleaning, foundSize: smart.foundSize)
    }

    var body: some View {
        ZStack {
            CategoryBackground(section: .cleaning)
            if smart.stage == .scanning {
                progress
            } else if hasResults || browsingTools {
                summary
            } else {
                introduction
            }
        }
    }

    private var introduction: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    HStack(spacing: 48) {
                        artwork.frame(width: 280, height: 300)
                        VStack(alignment: .leading, spacing: 22) {
                            Text("Nettoyage").font(.system(size: 44, weight: .regular))
                                .accessibilityAddTraits(.isHeader)
                            Text("Repérez ce qui peut être retiré de votre Mac. L’analyse prépare un bilan ; vous choisissez ensuite les éléments à nettoyer.")
                                .font(.system(size: 18)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            VStack(alignment: .leading, spacing: 20) {
                                OverviewFeatureRow(symbol: "sparkles", title: "Analyser les catégories de votre profil", tint: Theme.accentInk)
                                OverviewFeatureRow(symbol: "list.bullet.rectangle", title: "Examiner les résultats en détail", tint: Theme.accentInk)
                                OverviewFeatureRow(symbol: "checkmark.shield", title: "Garder le contrôle de chaque suppression", tint: Theme.accentInk)
                            }.padding(.top, 10)
                        }
                        .frame(maxWidth: 450, alignment: .leading)
                    }
                    .padding(36).frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
            OverviewActionFooter(caption: "Profil \(CleaningProfile(rawValue: profile)?.title ?? "Recommandé") · aucune suppression pendant l’analyse.",
                                 message: smart.statusMessage) {
                Button("Analyser") { analyze() }
                    .buttonStyle(CircularOverviewActionStyle(tint: ModuleColor.clean))
                    .accessibilityLabel("Analyser les catégories de nettoyage")
            } secondary: {
                Button("Accéder directement aux outils") { app.cleaningToolsVisible = true }
                    .buttonStyle(SecondaryActionButtonStyle()).font(AppFont.secondary)
            }
        }
    }


    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 55)
                .fill(LinearGradient(colors: [Theme.accent.shade(0.25), ModuleColor.privacy.shade(-0.4)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 55).strokeBorder(Color.white.opacity(0.25)))
                .shadow(color: Theme.accent.opacity(0.3), radius: 24, y: 14)
                .frame(width: 235, height: 235).rotationEffect(.degrees(-8))
            Image(systemName: "sparkles").font(.system(size: 115, weight: .light)).foregroundStyle(.white)
            Image(systemName: "checkmark.shield.fill").font(.system(size: 58))
                .symbolRenderingMode(.palette).foregroundStyle(.white, Theme.accent)
                .offset(x: 105, y: 100)
        }.accessibilityHidden(true)
    }

    private var progress: some View {
        AnalysisProgressView(title: "Analyse de votre Mac…", detail: smart.currentLabel ?? "Préparation de l’analyse…", symbol: "sparkles", cancel: { smart.cancelScan() }) {
            Text("\(smart.liveEntries.formatted()) entrées lues · \(humanSize(smart.liveBytes))")
        }
    }

    private var summary: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenToolbar(title: "Nettoyage") {
                    Button { analyze() } label: { Label(smart.hasRun ? "Relancer l’analyse" : "Analyser mon Mac", systemImage: "arrow.clockwise") }
                        .buttonStyle(SecondaryActionButtonStyle()).disabled(smart.stage == .cleaning)
                } trailing: { EmptyView() }
                VStack(spacing: 12) {
                    Text(hasResults ? result.title : "Choisissez votre nettoyage")
                        .font(.system(size: 32, weight: .semibold))
                        .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                    Text(hasResults ? result.detail : "Chaque outil vous laisse examiner les éléments avant toute action.")
                        .font(.system(size: 16)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                    if hasResults {
                        Button("Examiner les résultats") { app.module = .smartScan }
                            .font(.system(size: 16, weight: .semibold)).buttonStyle(OverviewPrimaryStyle())
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        categoryCard.frame(width: 310)
                        VStack(spacing: 18) { trashCard; systemCard }.frame(minWidth: 350)
                    }
                    VStack(spacing: 18) { categoryCard; trashCard; systemCard }
                }
                if developerTools { developerOptions }
                InterfaceHelp(title: "À propos du bilan", message: "Les corbeilles et le nettoyage système sont traités séparément du total de l’analyse.")
            }
            .padding(.horizontal, 36).padding(.vertical, 24)
            .frame(maxWidth: 1050).frame(maxWidth: .infinity)
        }
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            icon("line.3.horizontal.decrease.circle", color: Theme.accent)
            Text("Un nettoyage ciblé").font(.system(size: 23, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Choisissez une catégorie précise et examinez les fichiers proposés.")
                .font(AppFont.body).foregroundStyle(Theme.muted)
            Spacer(minLength: 4)
            Button("Choisir une catégorie") { app.module = .cleaning }
                .buttonStyle(SecondaryActionButtonStyle()).controlSize(.large)
        }
        .padding(22).frame(maxWidth: .infinity, minHeight: 270, alignment: .topLeading)
        .background(cardSurface)
    }

    private var trashCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Corbeilles").font(.system(size: 21, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    if trash.isLoading {
                        ProgressView("Mesure en cours…").font(AppFont.secondary)
                    } else {
                        Text(trashDetail).font(AppFont.body).foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 0)
                icon("trash", color: ModuleColor.clean)
            }
            Button("Examiner les corbeilles") { app.module = .trash }
                .buttonStyle(SecondaryActionButtonStyle()).controlSize(.large)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .topLeading).background(cardSurface)
    }

    private var trashDetail: String {
        if trash.statusMessage != nil { return "Mesure indisponible. Consultez le détail." }
        if !trash.hasLoaded { return "Vérifiez leur contenu avant un vidage définitif." }
        if trash.hasUnreadable { return "Au moins \(humanSize(trash.totalSize)) · certaines corbeilles sont illisibles." }
        return "\(humanSize(trash.totalSize)) déjà dans les corbeilles. Le vidage est définitif."
    }

    private var systemCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Journaux système").font(.system(size: 21, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Text("Examinez les anciens journaux. L’assistant est facultatif.")
                        .font(AppFont.body).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                icon("lock.shield", color: ModuleColor.maint)
            }
            Button("Examiner les journaux") { app.module = .systemClean }
                .buttonStyle(SecondaryActionButtonStyle()).controlSize(.large)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .topLeading).background(cardSurface)
    }

    private var developerOptions: some View {
        DisclosureGroup("Outils pour développeurs") {
            HStack(spacing: 18) {
                Button("Examiner les caches développeurs") { app.module = .devJunk }
                Button("Gérer les simulateurs") { app.module = .simulators }
                Spacer(minLength: 0)
            }.buttonStyle(SecondaryActionButtonStyle()).controlSize(.large).padding(.top, 12)
        }
        .font(AppFont.body).padding(16).background(cardSurface)
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.065))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.1)))
    }

    private func icon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 28, weight: .medium))
            .foregroundStyle(color.shade(0.5)).frame(width: 42, height: 42).accessibilityHidden(true)
    }

    private func analyze() {
        app.cleaningToolsVisible = false
        smart.scan()
        if smart.stage == .scanning && !trash.isLoading && !trash.isEmptying { trash.load() }
    }
}
