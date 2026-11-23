import SwiftUI
import AppKit
import Combine

/// Les modules de l'app, dans l'ordre de la barre latérale.
enum Module: String, CaseIterable, Identifiable {
    case dashboard, smartScan, applicationsOverview, cleaningOverview, filesOverview, toolsOverview, performanceOverview
    case cleaning, space, largeFiles, duplicates, trash, systemClean, uninstall, simulators, devJunk, startup, privacy, updates, maintenance
    case screenCleaning, aiClutter, applicationPermissions, battery, imageOptimization, diskHealth, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .about: return "À propos"
        case .battery: return "Batterie"
        case .dashboard: return "Accueil"
        case .applicationsOverview: return "Applications"
        case .cleaningOverview: return "Nettoyage"
        case .filesOverview: return "Mes fichiers"
        case .toolsOverview: return NavigationSection.tools.title
        case .performanceOverview: return "Performances"
        case .smartScan: return "Smart Scan"
        case .cleaning: return "Nettoyage"
        case .space: return "Espace disque"
        case .diskHealth: return "Santé des disques"
        case .imageOptimization: return "Alléger des images"
        case .largeFiles: return "Gros fichiers"
        case .duplicates: return "Doublons"
        case .trash: return "Corbeilles"
        case .systemClean: return "Nettoyage système"
        case .simulators: return "Simulateurs"
        case .uninstall: return "Désinstalleur"
        case .devJunk: return "Développement"
        case .startup: return "Démarrage"
        case .privacy: return "Confidentialité"
        case .updates: return "Mises à jour"
        case .maintenance: return "Maintenance"
        case .screenCleaning: return "Nettoyage d’écran"
        case .aiClutter: return "Fichiers IA inutiles"
        case .applicationPermissions: return "Autorisations des applications"
        }
    }

    var symbol: String {
        switch self {
        case .about: return "info.circle"
        case .battery: return "battery.100percent"
        case .dashboard: return "square.grid.2x2.fill"
        case .applicationsOverview: return "app.badge.fill"
        case .cleaningOverview: return "sparkles"
        case .filesOverview: return "folder.fill"
        case .toolsOverview: return "briefcase.fill"
        case .performanceOverview: return "bolt.fill"
        case .smartScan: return "sparkles"
        case .cleaning: return "sparkle.magnifyingglass"
        case .space: return "externaldrive.fill"
        case .diskHealth: return "internaldrive.fill"
        case .imageOptimization: return "photo.on.rectangle.angled"
        case .largeFiles: return "doc.richtext.fill"
        case .duplicates: return "doc.on.doc.fill"
        case .trash: return "trash.fill"
        case .systemClean: return "lock.shield.fill"
        case .simulators: return "iphone.gen3"
        case .uninstall: return "shippingbox.fill"
        case .devJunk: return "hammer.fill"
        case .startup: return "power"
        case .privacy: return "hand.raised.fill"
        case .updates: return "arrow.triangle.2.circlepath"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .screenCleaning: return "display"
        case .aiClutter: return "sparkles.rectangle.stack.fill"
        case .applicationPermissions: return "lock.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .about: return Theme.accent
        case .battery: return Theme.ok
        case .dashboard, .cleaning, .cleaningOverview: return ModuleColor.clean
        case .smartScan, .privacy: return ModuleColor.privacy
        case .space, .filesOverview: return ModuleColor.space
        case .largeFiles, .imageOptimization: return ModuleColor.space
        case .duplicates: return ModuleColor.space
        case .trash: return ModuleColor.clean
        case .systemClean: return ModuleColor.maint
        case .simulators: return ModuleColor.maint
        case .uninstall, .applicationsOverview: return ModuleColor.uninstall
        case .devJunk: return ModuleColor.maint
        case .startup, .performanceOverview: return ModuleColor.startup
        case .updates: return ModuleColor.updates
        case .maintenance, .toolsOverview, .diskHealth: return ModuleColor.maint
        case .screenCleaning: return .pink
        case .aiClutter: return .green
        case .applicationPermissions: return ModuleColor.privacy
        }
    }

    /// Tous les modules sont désormais implémentés.
    var isReady: Bool { true }

    /// Modules propres aux développeurs : masqués quand l'option est désactivée (Réglages).
    var isDeveloper: Bool { self == .devJunk || self == .simulators }

}

/// État global partagé : les modèles vivent ici, donc leur état survit à la navigation.
@MainActor
final class AppState: ObservableObject {
    @Published var module: Module? = .dashboard {
        didSet { if let module { navigationHistory.remember(module) } }
    }
    private var navigationHistory = NavigationHistory()
    @Published var applicationsDetail: ApplicationsDetail?
    @Published var cleaningToolsVisible = false
    @Published var performanceAnalyzed = false
    @Published var performanceDetail: PerformanceCategory?
    let battery = BatteryModel()
    let trayMetrics = TrayMetricsStore()
    let smartScan = SmartScanModel()
    let review = ReviewModel()
    let space = SpaceModel()
    let largeFiles = LargeFilesModel()
    let pngOptimization = PNGOptimizationModel()
    let filesAnalysis = FilesAnalysisModel()
    let duplicates = DuplicatesModel()
    let trash = TrashModel()
    let systemClean = SystemCleanModel()
    let simulators = SimulatorsModel()
    let uninstall = UninstallModel()
    let applicationsAnalysis = ApplicationsAnalysisModel()
    let applicationsInsights = ApplicationsInsightsModel()
    let applicationUpdateInstaller = ApplicationUpdateInstaller()
    let devJunk = DevJunkModel()
    let permissions = PermissionsModel()
    let startup = StartupModel()
    let privacy = PrivacyModel()
    let aiClutter = AIClutterModel()
    let applicationPermissions = ApplicationPermissionsModel()
    let screenCleaning = ScreenCleaningController()
    let updates = UpdatesModel()
    let maintenance = MaintenanceModel()
    let performanceTasks = PerformanceTasksModel()
    /// Analyse planifiée (créée avec l'état : elle tourne tant que l'app est ouverte).
    private(set) var scheduler: ScanScheduler!
    /// Ouvre la fenêtre principale ; renseigné par la première vue qui dispose de `openWindow`.
    var openMainWindow: (() -> Void)?

    init() {
        AppDelegate.stopBatteryBeforeTermination = { [weak battery] in await battery?.prepareForTermination() }
        battery.openSection = { [weak self] in self?.show(.battery) }
        scheduler = ScanScheduler(smart: smartScan) { [weak self] in self?.show(.smartScan) }
    }

    func select(_ section: NavigationSection) {
        applicationsDetail = nil
        switch section {
        case .applications: module = .applicationsOverview
        case .cleaning: module = .cleaningOverview
        case .files: module = .filesOverview
        case .tools: module = .toolsOverview
        case .performance:
            performanceDetail = nil
            module = .performanceOverview
        default: module = navigationHistory.destination(for: section, developerTools: DeveloperTools.enabled)
        }
    }

    func openTool(_ destination: Module) {
        module = destination
        if destination == .aiClutter { aiClutter.scan() }
        if destination == .applicationPermissions { applicationPermissions.scan() }
    }

    /// Ramène MacCare au premier plan sur un module (fenêtre rouverte si elle était fermée).
    func show(_ m: Module) {
        module = m
        DockVisibilityController.activateForWindow()
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { openMainWindow?() }
    }
}

struct RootView: View {
    @ObservedObject var app: AppState
    @ObservedObject var updater: AppUpdater
    @ObservedObject private var permissions: PermissionsModel
    @State private var displayLayout = MainWindowLayout.standard

    init(app: AppState, updater: AppUpdater) {
        self.app = app
        self.updater = updater
        self.permissions = app.permissions
    }

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            CategoryTransitionBackground(section: (app.module ?? .dashboard).section)
            if permissions.needsOnboarding {
                OnboardingView(model: app.permissions, system: app.systemClean)
                    .modifier(DisplayAdjustedContent(layout: displayLayout))
            } else {
                DetailView(app: app, updater: updater, layout: displayLayout)
                    .padding(.leading, SidebarLabel.railWidth * displayLayout.scale)
                    .overlay(alignment: .leading) {
                        Sidebar(app: app, updater: updater).dashboardBlockScale(displayLayout.scale)
                    }
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .frame(minWidth: displayLayout.minimumContentSize.width, minHeight: displayLayout.minimumContentSize.height)
        .onAppear {
            app.permissions.recheck()
            app.systemClean.refreshStatus()
            app.openMainWindow = { openWindow(id: MacCareApp.mainWindowID) }
            AppDelegate.openMainWindow = app.openMainWindow
        }
        // Après avoir activé l'autorisation dans Réglages, on revérifie dès le retour dans l'app.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.permissions.recheck()
            app.systemClean.refreshStatus()
        }
        .preferredColorScheme(.dark)   // Fonds colorés profonds, texte clair.
        .tint((app.module ?? .dashboard).section.palette.accent)
        .font(AppFont.body)
        .foregroundStyle(Theme.fg)
        .lineSpacing(3)
        .background(WindowConfigurator())
        .background(MainWindowDisplayObserver { displayLayout = $0 })
    }
}

/// Le rail garde sa largeur dans la mise en page. Les libellés se déploient au-dessus du détail.
struct Sidebar: View {
    @ObservedObject var updater: AppUpdater
    @ObservedObject var app: AppState
    @ObservedObject private var space: SpaceModel
    @ObservedObject private var smart: SmartScanModel
    @ObservedObject private var large: LargeFilesModel
    @ObservedObject private var duplicates: DuplicatesModel
    @ObservedObject private var applications: ApplicationsAnalysisModel
    @ObservedObject private var uninstall: UninstallModel
    @ObservedObject private var updates: UpdatesModel
    @ObservedObject private var performanceStartup: StartupModel
    @ObservedObject private var performanceTasks: PerformanceTasksModel
    @ObservedObject private var performanceRepairs: MaintenanceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var showingTools = false
    private var compact: Bool { !expanded && !showingTools }

    init(app: AppState, updater: AppUpdater) {
        self.updater = updater
        self.app = app; self.space = app.space; self.smart = app.smartScan
        self.large = app.largeFiles; self.duplicates = app.duplicates
        self.applications = app.applicationsAnalysis; self.uninstall = app.uninstall; self.updates = app.updates
        self.performanceStartup = app.startup; self.performanceTasks = app.performanceTasks; self.performanceRepairs = app.maintenance
    }
    private func activity(_ section: NavigationSection) -> (busy: Bool, available: Bool) {
        switch section {
        case .space: return (space.isLoading, space.hasMeasured)
        case .cleaning: return (smart.stage == .scanning || smart.stage == .cleaning, smart.hasRun)
        case .files: return (large.stage == .scanning || duplicates.stage == .scanning,
                             large.stage == .results || duplicates.stage == .results)
        case .performance: return (performanceStartup.isLoading || performanceTasks.isBusy || performanceRepairs.running != nil,
                                    app.performanceAnalyzed)
        case .applications: return (applications.phase == .inventory || uninstall.isScanningLeftovers || uninstall.isScanning || updates.isChecking,
                                    applications.phase == .summary)
        default: return (false, false)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ScrollView(.vertical) {
                VStack(spacing: 5) {
                    ForEach(NavigationSection.primary.filter { $0 != .tools && $0 != .about }) { row($0) }
                }
            }
            .scrollIndicators(.hidden)
            if (app.module ?? .dashboard).section != .home {
                Button { showingTools.toggle() } label: {
                    SidebarLabel(title: "Accès rapide", symbol: "square.grid.2x2", compact: compact)
                }
                .buttonStyle(SidebarRowStyle(selected: app.module?.section == .tools))
                .accessibilityLabel("Accès rapide").help("Accès rapide aux outils")
                .popover(isPresented: $showingTools, arrowEdge: .trailing) {
                    QuickToolsList(app: app) { showingTools = false; expanded = false }
                }
            }
            row(.about)
            Divider().padding(.vertical, 3)
            Button { expanded = compact } label: {
                SidebarLabel(title: compact ? "Développer" : "Réduire", symbol: "sidebar.left", compact: compact)
            }
            .buttonStyle(SidebarRowStyle(selected: false))
            .accessibilityLabel(compact ? "Développer la navigation" : "Réduire la navigation")
            .help(compact ? "Développer la navigation" : "Réduire la navigation")
        }
        .padding(.horizontal, 8)
        .padding(.top, 62)
        .padding(.bottom, 14)
        .frame(width: compact ? SidebarLabel.railWidth : 222)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topLeading) {
            if AppBuildIdentity.isDevelopment {
                Text(compact ? "Dev" : AppBuildIdentity.name)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.warn)
                    .padding(.leading, 21).padding(.top, 37).allowsHitTesting(false)
            }
        }
        .background((app.module ?? .dashboard).section.palette.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.08)).frame(width: 1) }
        .clipped()
        .shadow(color: .black.opacity(compact ? 0 : 0.25), radius: 12, x: 4)
        .contentShape(Rectangle())
        .onHover { expanded = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.19), value: compact)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            expanded = false
        }
    }

    @ViewBuilder
    private func row(_ m: NavigationSection) -> some View {
        if m == .about {
            AboutSidebarButton(selected: app.module == .about, compact: compact,
                               updateAvailable: updater.availableVersion != nil) { app.select(.about) }
        } else {
            let selected = (app.module ?? .dashboard).section == m
            Button { app.select(m) } label: {
                SidebarLabel(title: m.title, symbol: m.symbol, compact: compact)
            }
            .buttonStyle(SidebarRowStyle(selected: selected))
            .overlay(alignment: compact ? .topTrailing : .trailing) {
                // Rail : pastille à l'angle de l'icône. Barre complète : en fin de ligne, dans son axe.
                Group {
                    if activity(m).busy {
                        ScanActivityRing(lineWidth: 2, color: .white).frame(width: 14, height: 14)
                            .padding(3).background(Theme.window, in: Circle())
                    } else if activity(m).available {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
                            .foregroundStyle(Theme.ok).background(Theme.window, in: Circle())
                    }
                }
                .padding(.top, compact ? 4 : 0).padding(.trailing, compact ? 8 : 12)
                .accessibilityHidden(true).allowsHitTesting(false)
            }
            .accessibilityLabel(m.title)
            .accessibilityValue(activity(m).busy ? "Analyse en cours" : (activity(m).available ? "Résultats disponibles" : ""))
            .help(m.title + (activity(m).busy ? " · analyse en cours" : ""))
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

struct DetailView: View {
    @ObservedObject var app: AppState
    @ObservedObject var updater: AppUpdater
    let layout: MainWindowLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var filesManagerVisible: Bool { app.module == .largeFiles || app.module == .duplicates || app.module == .imageOptimization }
    private var filesPanelTransition: AnyTransition {
        ManagerPanelMotion.transition(reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionNavigationView(module: $app.module)
                .dashboardBlockScale(layout.scale)
            ZStack {
                Group {
                    if (app.module ?? .dashboard) == .dashboard {
                        // Le tableau AppKit garde les coordonnées natives, y compris pendant la navigation.
                        modulePage
                    } else {
                        modulePage.modifier(DisplayAdjustedContent(layout: layout))
                    }
                }
                .id(app.module)
                .transition(filesManagerVisible ? filesPanelTransition : ManagerPanelMotion.page(reduceMotion: reduceMotion))
                .zIndex(filesManagerVisible ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(reduceMotion ? nil : Motion.easeOut(0.2), value: app.module)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var modulePage: some View {
        switch app.module ?? .dashboard {
        case .about: AboutView(updater: updater)
        case .battery: BatteryView(model: app.battery)
        case .dashboard: DashboardView(app: app, layout: layout)
        case .applicationsOverview: ApplicationsOverviewView(app: app)
        case .cleaningOverview: CleaningOverviewView(app: app)
        case .filesOverview: FilesOverviewView(app: app)
        case .toolsOverview: ToolsOverviewView(app: app)
        case .performanceOverview: PerformanceOverviewView(app: app)
        case .smartScan, .cleaning, .trash, .systemClean, .simulators, .devJunk:
            CleaningDetailPanel(app: app, module: app.module ?? .cleaning)
        case .space: SpaceView(model: app.space)
        case .imageOptimization: PNGOptimizationView(model: app.pngOptimization) { app.module = .filesOverview }
        case .largeFiles: FilesManagerView(app: app, category: .large)
        case .duplicates: FilesManagerView(app: app, category: .duplicates)
        case .uninstall:
            ApplicationsDetailPanel(app: app, detail: app.uninstall.showingLeftovers ? .leftovers : .installed) {
                app.module = .applicationsOverview
            }
        case .updates:
            ApplicationsDetailPanel(app: app, detail: .updates, includeAllUpdateSources: true) {
                app.module = .applicationsOverview
            }
        case .startup, .privacy, .maintenance, .screenCleaning, .aiClutter, .applicationPermissions, .diskHealth:
            ToolsDetailPanel(app: app, module: app.module ?? .toolsOverview)
        }
    }
}

/// En-tête d'écran réutilisable.
struct ScreenHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(AppFont.pageTitle)
            Text(subtitle).font(AppFont.body).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
