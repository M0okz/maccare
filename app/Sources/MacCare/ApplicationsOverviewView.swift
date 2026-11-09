import SwiftUI

/// Entrée de la rubrique : découvrir, analyser, puis choisir un résultat à examiner.
struct ApplicationsOverviewView: View {
    @ObservedObject var app: AppState
    @ObservedObject private var analysis: ApplicationsAnalysisModel
    @ObservedObject private var uninstall: UninstallModel
    @ObservedObject private var updates: UpdatesModel
    @ObservedObject private var insights: ApplicationsInsightsModel
    @State private var previewURLs: [URL] = []
    @ScaledMetric(relativeTo: .title) private var overviewTitleSize: CGFloat = 28
    @ScaledMetric(relativeTo: .title2) private var updateTitleSize: CGFloat = 21
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var detail: ApplicationsDetail? { app.applicationsDetail }

    init(app: AppState) {
        self.app = app
        self.analysis = app.applicationsAnalysis
        self.uninstall = app.uninstall
        self.updates = app.updates
        self.insights = app.applicationsInsights
    }

    private var updateSummary: ApplicationUpdateSummary { ApplicationUpdateSummary(sources: updates.sources) }
    private var working: Bool { uninstall.isScanningLeftovers || updates.isChecking || insights.isScanning || analysis.phase == .inventory }

    var body: some View {
        ZStack {
            overview.allowsHitTesting(detail == nil).accessibilityHidden(detail != nil)
            if let destination = detail {
                ApplicationsDetailPanel(app: app, detail: destination)
                    .transition(ManagerPanelMotion.transition(reduceMotion: reduceMotion)).zIndex(1)
            }
        }.clipped()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: detail)
            .onAppear { if !updates.isChecking { refreshPreview() } }
            .onChange(of: updates.isChecking) { checking in
                if checking { previewURLs = [] } else { refreshPreview() }
            }
    }

    private var overview: some View {
        ZStack {
            CategoryBackground(section: .applications)
            if analysis.phase == .inventory {
                AnalysisProgressView(title: "Inventaire de vos applications…", detail: "Le bilan apparaîtra dès que la liste sera prête. Les contrôles de mises à jour se poursuivront dans le bilan.", symbol: "square.stack.3d.up.fill", color: ModuleColor.uninstall) {
                    Text("\(uninstall.apps.count) applications répertoriées")
                }
            } else if analysis.phase == .summary {
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
                            Text("Applications")
                                .font(.system(size: 44, weight: .regular))
                                .accessibilityAddTraits(.isHeader)
                            Text("Faites le point sur vos apps. Retrouvez les mises à jour, les apps à examiner et les installateurs téléchargés.")
                                .font(.system(size: 18)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            VStack(alignment: .leading, spacing: 20) {
                                OverviewFeatureRow(symbol: "app.badge", title: "Gérer les applications installées", tint: Theme.accentInk)
                                OverviewFeatureRow(symbol: "arrow.triangle.2.circlepath", title: "Consulter les mises à jour", tint: Theme.accentInk)
                                OverviewFeatureRow(symbol: "clock", title: "Examiner les apps peu utilisées et les installateurs", tint: Theme.accentInk)
                            }.padding(.top, 10)
                        }
                        .frame(maxWidth: 450, alignment: .leading)
                    }
                    .padding(36)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
            OverviewActionFooter(caption: "Analyse seule. Vous choisissez ensuite ce que vous souhaitez faire.") {
                if analysis.phase == .inventory {
                    ProgressView("Inventaire de vos applications…").font(AppFont.body).frame(minHeight: 90)
                } else {
                    Button("Analyser") { analyze() }
                        .buttonStyle(CircularOverviewActionStyle(tint: ModuleColor.uninstall))
                        .accessibilityLabel("Analyser les applications")
                }
            }
        }
    }


    /// Illustration vectorielle propre à MacCare ; elle ne contient aucun contrôle.
    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 55)
                .fill(LinearGradient(colors: [ModuleColor.space.shade(0.25), Theme.accent.shade(-0.45)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 55).strokeBorder(Color.white.opacity(0.25)))
                .shadow(color: ModuleColor.space.opacity(0.3), radius: 24, y: 14)
                .frame(width: 235, height: 235).rotationEffect(.degrees(-8))
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 115, weight: .light))
                .foregroundStyle(Color.white.opacity(0.94))
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 58))
                .symbolRenderingMode(.palette).foregroundStyle(.white, Theme.accent)
                .offset(x: 105, y: 100)
        }
        .accessibilityHidden(true)
    }

    private var summary: some View {
        VStack(spacing: 0) {
            ScreenToolbar(title: "Applications") {
                Button(action: prepareNewAnalysis) { Label("Recommencer", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(ToolbarActionButtonStyle()).disabled(working || uninstall.isCleaning)
                    .help("Revenir à l’écran Analyser pour préparer un nouveau bilan.")
            } trailing: { EmptyView() }
                .padding(.horizontal, 32).frame(height: 56).padding(.vertical, 8)
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 14) {
                        Text("\(uninstall.apps.count) application\(uninstall.apps.count == 1 ? "" : "s") sur ce Mac.")
                            .font(.system(size: overviewTitleSize, weight: .semibold))
                            .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                        Text(working ? "Votre bilan se complète. Vous pouvez déjà gérer vos applications." : "Votre bilan est prêt. Choisissez ce que vous souhaitez examiner.")
                            .font(.system(size: 16)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                        Button("Gérer mes applications") { open(.installed) }
                        .font(.system(size: 16, weight: .semibold))
                        .buttonStyle(OverviewPrimaryStyle())
                    }
                    .padding(.bottom, 4)

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            updatesCard.frame(width: 310)
                            insightCards.frame(minWidth: 350)
                        }
                        VStack(spacing: 18) { updatesCard; insightCards }
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) { leftoversCard; startupCard }
                        VStack(spacing: 18) { leftoversCard; startupCard }
                    }
                    Text("Rien n’est supprimé ni installé pendant l’analyse.")
                        .font(AppFont.secondary).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 36).padding(.top, 16).padding(.bottom, 24)
                .frame(maxWidth: 1050).frame(maxWidth: .infinity)
            }
        }
    }

    private var updatesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 24, weight: .medium))
                    .foregroundStyle(ModuleColor.updates.shade(0.5)).frame(height: 28).accessibilityHidden(true)
                Spacer()
                HStack(spacing: 2) {
                    Text("MISES À JOUR").font(AppFont.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                    ApplicationCardInfoButton(information: .updates) { open(.updates) }
                }
            }
            Text(updateSummary.title).font(.system(size: updateTitleSize, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            Text(updateSummary.detail).font(AppFont.secondary).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if updateSummary.checking { ProgressView().controlSize(.small) }
            Spacer(minLength: 0)
            if !previewURLs.isEmpty { ApplicationUpdateIconPreview(urls: previewURLs, totalCount: updateSummary.count) }
            Spacer(minLength: 0)
            Button("Voir les mises à jour") { open(.updates) }
                .buttonStyle(SecondaryActionButtonStyle()).controlSize(.large)
        }
        .padding(22).frame(maxWidth: .infinity, minHeight: 346, alignment: .topLeading)
        .background(cardSurface)
    }

    private var insightCards: some View {
        VStack(spacing: 18) {
            if insights.isScanning {
                HStack(spacing: 12) { ProgressView().controlSize(.small); Text("Vérification de l’utilisation, de la compatibilité et des installateurs…").font(AppFont.secondary) }
                    .padding(22).frame(maxWidth: .infinity, minHeight: 164, alignment: .leading).background(cardSurface)
            } else {
                ApplicationsInsightCard(title: insights.snapshot.unused.isEmpty ? "Applications peu utilisées" : "\(insights.snapshot.unused.count) application\(insights.snapshot.unused.count == 1 ? "" : "s") peu utilisée\(insights.snapshot.unused.count == 1 ? "" : "s")",
                    detail: insights.snapshot.unused.isEmpty ? "Aucune ouverture ancienne retenue. Seuil : 30 jours ; les dates inconnues sont écartées." : "Aucune ouverture enregistrée depuis au moins 30 jours. Examinez les apps avant de décider.",
                    symbol: "clock.badge.questionmark", tint: ModuleColor.uninstall, information: .unused,
                    actionTitle: insights.snapshot.unused.isEmpty ? "Comprendre le calcul" : "Examiner les applications") { open(.unused) }
                HStack(alignment: .top, spacing: 18) {
                    if !insights.snapshot.incompatible.isEmpty {
                        ApplicationsInsightCard(title: "\(insights.snapshot.incompatible.count) application\(insights.snapshot.incompatible.count == 1 ? "" : "s") incompatible\(insights.snapshot.incompatible.count == 1 ? "" : "s")",
                            detail: "Architecture ou version minimale de macOS non prise en charge sur ce Mac.", symbol: "exclamationmark.triangle.fill", tint: Theme.warn, information: .incompatible,
                            actionTitle: "Examiner") { open(.incompatible) }
                    }
                    if !insights.snapshot.installers.isEmpty {
                        ApplicationsInsightCard(title: "\(humanSize(insights.installerBytes)) de fichiers d’installation",
                            detail: "\(insights.snapshot.installers.count) fichiers DMG ou PKG dans Téléchargements. À examiner avant de retirer.",
                            symbol: "shippingbox.fill", tint: ModuleColor.space, information: .installers, actionTitle: "Examiner") { open(.installers) }
                    }
                }
                if let error = insights.snapshot.installerError { Text(error).font(AppFont.secondary).foregroundStyle(Theme.muted) }
            }
        }
    }

    private func refreshPreview() {
        let entries = ApplicationUpdatePresentation.entries(sources: updates.sources, apps: uninstall.apps, query: "", sort: .name, lastOpened: [:])
        var seen = Set<URL>()
        let urls = entries.compactMap { $0.applicationURL(in: uninstall.apps) }
            .filter { FileManager.default.fileExists(atPath: $0.path) && seen.insert($0).inserted }
        previewURLs = Array(urls.shuffled().prefix(3))
    }

    private var leftoversCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(uninstall.isScanningLeftovers ? "Recherche de données oubliées…" : "Données d’applications supprimées")
                            .font(.system(size: 21, weight: .semibold)).accessibilityAddTraits(.isHeader)
                        ApplicationCardInfoButton(information: .leftovers, arrowEdge: .top) { open(.leftovers) }
                    }
                    if uninstall.isScanningLeftovers {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(uninstall.leftovers.isEmpty ? "Aucune donnée oubliée détectée." : "\(humanSize(uninstall.leftoverTotal)) à examiner · \(uninstall.leftovers.count) \(pl(uninstall.leftovers.count, "élément"))")
                            .font(.system(size: 17)).foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 0)
                cardIcon("shippingbox", color: ModuleColor.uninstall)
            }
            if !uninstall.isScanningLeftovers && !uninstall.leftovers.isEmpty {
                Button("Examiner les données") { open(.leftovers) }.buttonStyle(SecondaryActionButtonStyle()).controlSize(.large)
            }
        }
        .padding(22).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(cardSurface)
    }

    private var startupCard: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("À l’ouverture du Mac").font(.system(size: 21, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    ApplicationCardInfoButton(information: .startup, arrowEdge: .top) { open(.startup) }
                }
                Text("Choisissez ce qui se lance à la connexion.")
                    .font(AppFont.body).foregroundStyle(Theme.muted)
                Button("Gérer le démarrage") { open(.startup) }
                    .buttonStyle(SecondaryActionButtonStyle()).controlSize(.large)
            }
            Spacer(minLength: 0)
            cardIcon("power", color: ModuleColor.startup)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(cardSurface)
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.white.opacity(0.065))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.1)))
    }

    private func cardIcon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 28, weight: .medium))
            .foregroundStyle(color.shade(0.5)).frame(width: 42, height: 42)
            .accessibilityHidden(true)
    }

    private func open(_ destination: ApplicationsDetail) {
        guard !uninstall.isCleaning else { return }
        if destination == .installed {
            uninstall.showingLeftovers = false
            uninstall.selectedApp = nil
        } else if destination == .leftovers {
            uninstall.showingLeftovers = true
        }
        app.applicationsDetail = destination
    }

    private func prepareNewAnalysis() {
        guard !working, !uninstall.isCleaning else { return }
        analysis.prepareForNewAnalysis()
        app.applicationsDetail = nil
    }

    private func analyze() { analysis.analyze(uninstall: uninstall, updates: updates, insights: insights) }
}
