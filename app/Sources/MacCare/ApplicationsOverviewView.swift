import SwiftUI

/// Entrée de la rubrique : découvrir, analyser, puis choisir un résultat à examiner.
struct ApplicationsOverviewView: View {
    @ObservedObject var app: AppState
    @ObservedObject private var analysis: ApplicationsAnalysisModel
    @ObservedObject private var uninstall: UninstallModel
    @ObservedObject private var updates: UpdatesModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var detail: ApplicationsDetail? { app.applicationsDetail }

    init(app: AppState) {
        self.app = app
        self.analysis = app.applicationsAnalysis
        self.uninstall = app.uninstall
        self.updates = app.updates
    }

    private var updateSummary: ApplicationUpdateSummary { ApplicationUpdateSummary(sources: updates.sources) }
    private var working: Bool { uninstall.isScanningLeftovers || updates.isChecking || analysis.phase == .inventory }

    var body: some View {
        ZStack {
            overview.allowsHitTesting(detail == nil).accessibilityHidden(detail != nil)
            if let destination = detail {
                ApplicationsDetailPanel(app: app, detail: destination)
                    .transition(ManagerPanelMotion.transition(reduceMotion: reduceMotion)).zIndex(1)
            }
        }.clipped()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: detail)
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
                            Text("Faites le point sur vos apps. Retrouvez celles à désinstaller, les données oubliées et les mises à jour disponibles.")
                                .font(.system(size: 18)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            VStack(alignment: .leading, spacing: 20) {
                                OverviewFeatureRow(symbol: "app.badge", title: "Gérer les applications installées", tint: Theme.accentInk)
                                OverviewFeatureRow(symbol: "arrow.triangle.2.circlepath", title: "Consulter les mises à jour", tint: Theme.accentInk)
                                OverviewFeatureRow(symbol: "shippingbox", title: "Retrouver les données oubliées", tint: Theme.accentInk)
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
                VStack(spacing: 26) {
                    VStack(spacing: 14) {
                        Text("\(uninstall.apps.count) application\(uninstall.apps.count == 1 ? "" : "s") sur ce Mac.")
                            .font(.system(size: 32, weight: .semibold))
                            .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                        Text(working ? "Votre bilan se complète. Vous pouvez déjà gérer vos applications." : "Votre bilan est prêt. Choisissez ce que vous souhaitez examiner.")
                            .font(.system(size: 16)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                        Button("Gérer mes applications") { open(.installed) }
                        .font(.system(size: 16, weight: .semibold))
                        .buttonStyle(OverviewPrimaryStyle())
                    }
                    .padding(.bottom, 10)

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            updatesCard.frame(width: 310)
                            VStack(spacing: 18) { leftoversCard; startupCard }.frame(minWidth: 350)
                        }
                        VStack(spacing: 18) { updatesCard; leftoversCard; startupCard }
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
        VStack(alignment: .leading, spacing: 16) {
            cardIcon("arrow.triangle.2.circlepath", color: ModuleColor.updates)
            Text(updateSummary.title).font(.system(size: 23, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            Text(updateSummary.detail).font(AppFont.body).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if updateSummary.checking { ProgressView().controlSize(.small) }
            Spacer(minLength: 4)
            Button("Voir les mises à jour") { open(.updates) }
                .buttonStyle(SecondaryActionButtonStyle()).controlSize(.large)
        }
        .padding(22).frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .background(cardSurface)
    }

    private var leftoversCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(uninstall.isScanningLeftovers ? "Recherche de données oubliées…" : "Données d’applications supprimées")
                        .font(.system(size: 21, weight: .semibold)).accessibilityAddTraits(.isHeader)
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
                Text("À l’ouverture du Mac").font(.system(size: 21, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
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

    private func analyze() { analysis.analyze(uninstall: uninstall, updates: updates) }
}
