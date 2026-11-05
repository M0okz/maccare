import SwiftUI
import MacCareMaintenance

struct PerformanceOverviewView: View {
    @ObservedObject var app: AppState
    @ObservedObject private var startup: StartupModel
    @ObservedObject private var permissions: PermissionsModel
    @ObservedObject private var tasks: PerformanceTasksModel
    @ObservedObject private var repairs: MaintenanceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize: CGFloat = 44
    @ScaledMetric(relativeTo: .title) private var summarySize: CGFloat = 32

    init(app: AppState) {
        self.app = app; startup = app.startup; permissions = app.permissions
        tasks = app.performanceTasks; repairs = app.maintenance
    }
    private var writing: Bool { tasks.running != nil || repairs.running != nil || startup.busyPath != nil }
    private var summaryTitle: String {
        if startup.statusMessage != nil { return "Votre bilan du démarrage est partiel" }
        return startup.loginItemsLoaded ? "\(startup.total) \(pl(startup.total, "élément")) à examiner" : "\(startup.agents.count) \(pl(startup.agents.count, "élément")) d’arrière-plan"
    }
    var body: some View {
        ZStack {
            overview.allowsHitTesting(app.performanceDetail == nil).accessibilityHidden(app.performanceDetail != nil)
            if let category = app.performanceDetail {
                PerformanceDetailPanel(app: app, category: category)
                    .transition(ManagerPanelMotion.transition(reduceMotion: reduceMotion)).zIndex(1)
            }
        }.clipped().animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: app.performanceDetail)
    }
    private var overview: some View {
        ZStack {
            CategoryBackground(section: .performance)
            if app.performanceAnalyzed && startup.isLoading {
                AnalysisProgressView(title: "Examen du démarrage…", detail: "Lecture des applications à la connexion et des agents accessibles.", symbol: "bolt.fill", color: ModuleColor.startup) { EmptyView() }
            } else if app.performanceAnalyzed { summary }
            else { introduction }
        }
    }
    private var introduction: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 48) { artwork.frame(width: 280, height: 300); introductionText.frame(width: 450) }
                        VStack(spacing: 24) { artwork; introductionText }
                    }.padding(36).frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
            OverviewActionFooter(caption: "Analyse seule. Vous choisissez ensuite les éléments à gérer.") {
                Button("Analyser", action: analyze)
                    .buttonStyle(CircularOverviewActionStyle(tint: ModuleColor.startup))
                    .accessibilityLabel("Analyser les performances").disabled(writing)
            } secondary: {
                Button("Examiner une catégorie directement") { app.performanceDetail = .maintenance }
                    .buttonStyle(SecondaryActionButtonStyle()).font(AppFont.secondary).disabled(writing)
            }
        }
    }
    private var introductionText: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Performances").font(.system(size: headingSize)).accessibilityAddTraits(.isHeader)
            Text("Faites le point sur le démarrage de votre Mac et retrouvez les outils d’entretien adaptés à votre situation.")
                .font(.system(size: 18)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 20) {
                ForEach(PerformanceCategory.allCases) { category in
                    OverviewFeatureRow(symbol: category.symbol, title: category.title, tint: ModuleColor.startup.shade(0.4))
                }
            }.padding(.top, 10)
        }
    }
    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 52)
                .fill(LinearGradient(colors: [ModuleColor.startup.shade(0.15), ModuleColor.startup.shade(-0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 52).strokeBorder(.white.opacity(0.2))).rotationEffect(.degrees(-8))
            Image(systemName: "bolt.fill").font(.system(size: 112)).foregroundStyle(.white)
        }.frame(width: 235, height: 235).padding(22).accessibilityHidden(true)
    }
    private var summary: some View {
        VStack(spacing: 0) {
            ScreenToolbar(title: "Performances") {
                Button(action: analyze) { Label("Actualiser le bilan", systemImage: "arrow.clockwise") }
                    .buttonStyle(ToolbarActionButtonStyle()).disabled(startup.isLoading || writing)
            } trailing: { EmptyView() }.padding(.horizontal, 32).frame(height: 56).padding(.vertical, 8)
            ScrollView {
                VStack(spacing: 26) {
                    VStack(spacing: 14) {
                        Text(summaryTitle).font(.system(size: summarySize, weight: .semibold)).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                        Text("Choisissez ce qui se lance avec votre Mac et les outils d’entretien que vous souhaitez examiner.")
                            .font(AppFont.body).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }.padding(.vertical, 12)
                    if let error = startup.statusMessage {
                        Label(error, systemImage: "exclamationmark.triangle").font(AppFont.secondary).foregroundStyle(Theme.warn)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            categoryCard(.maintenance, tall: true).frame(width: 310)
                            VStack(spacing: 18) { categoryCard(.login); categoryCard(.background) }.frame(minWidth: 350)
                        }
                        VStack(spacing: 18) { categoryCard(.maintenance); categoryCard(.login); categoryCard(.background) }
                    }
                    InterfaceHelp(title: "À propos de ce bilan", message: "Ce bilan inventorie les éléments de démarrage accessibles et donne accès aux outils d’entretien. Il ne mesure pas la vitesse du Mac. Chaque modification et chaque tâche restent à votre choix, avec leurs précautions et confirmations.")
                }.padding(.horizontal, 36).padding(.top, 16).padding(.bottom, 24)
                    .frame(maxWidth: 1050).frame(maxWidth: .infinity)
            }
        }
    }
    private func categoryCard(_ category: PerformanceCategory, tall: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(category.title).font(AppFont.section.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text(summaryText(category)).font(AppFont.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: category.symbol).font(.title2).foregroundStyle(ModuleColor.startup.shade(0.4)).accessibilityHidden(true)
            }
            if tall {
                Text("Mail, caches, recherche et connexions : consultez le rôle de chaque tâche avant de la choisir.")
                    .font(AppFont.body).foregroundStyle(Theme.muted)
                Spacer(minLength: 16)
            }
            Button(category == .maintenance ? "Examiner les tâches" : "Examiner") { app.performanceDetail = category }
                .buttonStyle(SecondaryActionButtonStyle()).controlSize(.large).disabled(writing)
                .accessibilityLabel("Examiner : \(category.title)")
        }.padding(22).frame(maxWidth: .infinity, minHeight: tall ? 318 : 150, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.065)))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.1)))
    }
    private func summaryText(_ category: PerformanceCategory) -> String {
        switch category {
        case .maintenance: return "\(PerformanceTask.allCases.count) tâches d’entretien · \(repairs.tasks.count) réparations ciblées"
        case .login:
            guard permissions.automation == .granted else { return "Accès nécessaire pour lire les apps à la connexion." }
            guard startup.loginItemsError == nil, startup.statusMessage == nil else { return "Lecture incomplète · examinez les détails." }
            return startup.loginItemsLoaded ? "\(startup.loginItems.count) \(pl(startup.loginItems.count, "application")) à la connexion" : "Actualisez le bilan pour lire la liste."
        case .background:
            guard startup.statusMessage == nil else { return "Inventaire indisponible · examinez les détails." }
            return "\(startup.userAgents.count) \(pl(startup.userAgents.count, "agent")) de session · \(startup.systemAgents.count) système · \(startup.disabledAgents.count) \(pl(startup.disabledAgents.count, "désactivé"))"
        }
    }
    private func analyze() {
        guard !startup.isLoading, !writing else { return }
        app.performanceAnalyzed = true
        startup.load(includeLoginItems: permissions.automation == .granted)
    }
}
