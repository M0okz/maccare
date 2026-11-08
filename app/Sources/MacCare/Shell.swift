import SwiftUI
import AppKit
import Combine

/// Les modules de l'app, dans l'ordre de la barre latérale.
enum Module: String, CaseIterable, Identifiable {
    case dashboard, smartScan, applicationsOverview, cleaningOverview, filesOverview, toolsOverview, performanceOverview
    case cleaning, space, largeFiles, duplicates, trash, systemClean, uninstall, simulators, devJunk, startup, privacy, updates, maintenance
    case screenCleaning, aiClutter, applicationPermissions, battery, imageOptimization, diskHealth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .battery: return "Batterie"
        case .dashboard: return "Accueil"
        case .applicationsOverview: return "Applications"
        case .cleaningOverview: return "Nettoyage"
        case .filesOverview: return "Mes fichiers"
        case .toolsOverview: return "Outils"
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
    @Published private(set) var activity: [AppActivityEntry] = []
    private var subscriptions = Set<AnyCancellable>()
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
    var openCPUActivity: (() -> Void)?

    init() {
        AppDelegate.stopBatteryBeforeTermination = { [weak battery] in await battery?.prepareForTermination() }
        battery.openSection = { [weak self] in self?.show(.battery) }
        scheduler = ScanScheduler(smart: smartScan) { [weak self] in self?.show(.smartScan) }
        observeActivity()
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

    private func observeActivity() {
        smartScan.$lastCompletedAt.compactMap { $0 }.sink { [weak self] date in
            self?.recordActivity("Analyse terminée", detail: "Analyse seule · consultez les résultats avant toute action.", module: .smartScan, date: date)
        }.store(in: &subscriptions)
        let reports: [(Published<RemovalReport?>.Publisher, Module)] = [
            (smartScan.$lastReport, .smartScan), (review.$lastReport, .cleaning),
            (uninstall.$lastReport, .uninstall), (devJunk.$lastReport, .devJunk),
            (largeFiles.$lastReport, .largeFiles), (duplicates.$lastReport, .duplicates),
            (privacy.$lastReport, .privacy), (aiClutter.$lastReport, .aiClutter)
        ]
        for (publisher, destination) in reports {
            publisher.compactMap { $0 }.sink { [weak self] report in
                self?.recordActivity(destination.title, detail: report.summary, module: destination)
            }.store(in: &subscriptions)
        }
        performanceTasks.$lastSummary.compactMap { $0 }.sink { [weak self] summary in
            self?.recordActivity("Entretien", detail: summary, module: .performanceOverview)
        }.store(in: &subscriptions)
        let summaries: [(Published<String?>.Publisher, Module)] = [
            (trash.$lastSummary, .trash), (systemClean.$lastSummary, .systemClean),
            (simulators.$lastSummary, .simulators), (startup.$lastAction, .startup)
        ]
        for (publisher, destination) in summaries {
            publisher.compactMap { $0 }.sink { [weak self] summary in
                self?.recordActivity(destination.title, detail: summary, module: destination)
            }.store(in: &subscriptions)
        }
    }

    private func recordActivity(_ title: String, detail: String, module: Module, date: Date = Date()) {
        activity.insert(AppActivityEntry(date: date, title: title, detail: detail, module: module), at: 0)
        if activity.count > 30 { activity.removeLast(activity.count - 30) }
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
    @ObservedObject private var permissions: PermissionsModel
    @State private var displayLayout = MainWindowLayout.standard

    init(app: AppState) {
        self.app = app
        self.permissions = app.permissions
    }

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            CategoryTransitionBackground(section: (app.module ?? .dashboard).section)
            if permissions.needsOnboarding {
                OnboardingView(model: app.permissions, system: app.systemClean)
            } else {
                HStack(spacing: 0) {
                    Sidebar(app: app)
                    DetailView(app: app)
                }
                .ignoresSafeArea(.container, edges: .top)
            }
        }
        .modifier(DisplayAdjustedContent(layout: displayLayout))
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

/// Rend la barre de titre transparente : le dégradé violet monte jusqu'en haut (plus de bandeau gris).
struct WindowConfigurator: NSViewRepresentable {
    private static let sizeMigrationKey = "mainWindowSize1200x720Applied"

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { apply(to: nsView) }

    /// Ne configure que la fenêtre qui héberge cette vue, jamais les dialogues ou le panneau de menu.
    private func apply(to view: NSView, attempt: Int = 0) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                if attempt < 30 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        apply(to: view, attempt: attempt + 1)
                    }
                }
                return
            }
            // Une vraie barre d’outils donne aux boutons natifs une zone de titre plus haute.
            // AppKit conserve le dessin, les états actifs/inactifs, l’aide et les actions système.
            if window.toolbar == nil {
                let toolbar = NSToolbar(identifier: "MacCareMainWindowToolbar")
                toolbar.showsBaselineSeparator = false
                toolbar.allowsUserCustomization = false
                toolbar.displayMode = .iconOnly
                window.toolbar = toolbar
            }
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = AppBuildIdentity.name
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            window.backgroundColor = NSColor(Color(hex: "#160C2E"))
            // Aligne aussi une fenêtre restaurée de l'ancienne version, une seule fois.
            // Les redimensionnements manuels suivants restent mémorisés par macOS.
            let layout = window.screen.map { MainWindowDisplayObserver.layout(on: $0) } ?? .standard
            if !UserDefaults.standard.bool(forKey: Self.sizeMigrationKey) {
                window.setContentSize(layout.preferredWindowSize)
                window.center()
                UserDefaults.standard.set(true, forKey: Self.sizeMigrationKey)
            }
            if layout.isCompact && !UserDefaults.standard.bool(forKey: MainWindowLayout.compactWindowMigrationKey),
               !window.styleMask.contains(.fullScreen), !window.isMiniaturized {
                let current = window.contentView?.frame.size ?? window.frame.size
                let reduced = layout.reducedRestoredSize(current)
                if reduced.width < current.width || reduced.height < current.height {
                    window.setContentSize(reduced)
                    window.center()
                }
                UserDefaults.standard.set(true, forKey: MainWindowLayout.compactWindowMigrationKey)
            }
        }
    }
}

/// Barre latérale labellisée (icône + texte), translucide sur le dégradé violet de MacCare.
struct Sidebar: View {
    @ObservedObject var app: AppState
    @ObservedObject private var space: SpaceModel
    @ObservedObject private var smart: SmartScanModel
    @ObservedObject private var large: LargeFilesModel
    @ObservedObject private var duplicates: DuplicatesModel
    @ObservedObject private var filesAnalysis: FilesAnalysisModel
    @ObservedObject private var applications: ApplicationsAnalysisModel
    @ObservedObject private var uninstall: UninstallModel
    @ObservedObject private var updates: UpdatesModel
    @ObservedObject private var performanceStartup: StartupModel
    @ObservedObject private var performanceTasks: PerformanceTasksModel
    @ObservedObject private var performanceRepairs: MaintenanceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedDuringExploration = false

    init(app: AppState) {
        self.app = app; self.space = app.space; self.smart = app.smartScan
        self.large = app.largeFiles; self.duplicates = app.duplicates; self.filesAnalysis = app.filesAnalysis
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
    private var focusedExploration: Bool {
        activity((app.module ?? .dashboard).section).busy || (app.module == .space && space.hasMeasured) ||
            app.module == .largeFiles || app.module == .duplicates || app.module == .imageOptimization ||
            ((app.module ?? .dashboard).section == .tools && app.module != .toolsOverview) ||
            (app.module == .performanceOverview && (app.performanceAnalyzed || app.performanceDetail != nil)) ||
            (app.module == .applicationsOverview && (app.applicationsDetail != nil || applications.phase == .summary)) ||
            (app.module == .filesOverview && app.filesAnalysis.hasStarted && !app.filesAnalysis.choosingLocation)
    }
    private var compact: Bool { focusedExploration && !expandedDuringExploration }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(NavigationSection.primary) { row($0) }
            Spacer(minLength: 24)
            if focusedExploration {
                Button { expandedDuringExploration.toggle() } label: {
                    Image(systemName: compact ? "sidebar.left" : "sidebar.leading")
                        .font(.system(size: 18))
                        .frame(width: compact ? nil : 20)
                        .padding(.leading, compact ? 0 : 12)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: compact ? .center : .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(Theme.muted)
                    .accessibilityLabel(compact ? "Développer la navigation" : "Réduire la navigation")
                    .help(compact ? "Développer la navigation" : "Réduire la navigation")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 58)   // réserve la ligne des boutons natifs, sans bloc de marque
        .padding(.bottom, 20)
        .frame(width: compact ? 82 : 240)
        .animation(reduceMotion ? nil : Motion.easeInOut(0.25), value: compact)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topLeading) {
            if AppBuildIdentity.isDevelopment {
                Text(compact ? "Dev" : AppBuildIdentity.name)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.warn)
                    .padding(.leading, 20).padding(.top, 38).allowsHitTesting(false)
            }
        }
        .background(
            (app.module ?? .dashboard).section.palette.sidebar
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: (app.module ?? .dashboard).section)
        )
        .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1) }
    }

    private func row(_ m: NavigationSection) -> some View {
        let selected = (app.module ?? .dashboard).section == m
        return Button { app.select(m) } label: {
            HStack(spacing: 11) {
                Image(systemName: m.symbol)
                    .accessibilityHidden(true)
                    .font(AppFont.emphasis)
                    .foregroundStyle(selected ? Color.white : Theme.muted)
                    .frame(width: compact ? 24 : 20, height: 20)
                if !compact {
                    Text(m.title)
                        .font(AppFont.body.weight(.medium))
                        .foregroundStyle(Theme.fg)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, compact ? 0 : 12).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            .contentShape(Rectangle())
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

struct DetailView: View {
    @ObservedObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var filesManagerVisible: Bool { app.module == .largeFiles || app.module == .duplicates || app.module == .imageOptimization }
    private var filesPanelTransition: AnyTransition {
        ManagerPanelMotion.transition(reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(spacing: 0) {
            if app.module?.section == .applications && app.module != .applicationsOverview {
                HStack {
                    Button { app.module = .applicationsOverview } label: {
                        Label(app.applicationsAnalysis.phase == .summary ? "Bilan des applications" : "Applications", systemImage: "chevron.left")
                    }
                    .buttonStyle(SecondaryActionButtonStyle()).font(AppFont.body)
                    Spacer()
                }
                .padding(.horizontal, Space.xl).padding(.top, Space.l)
            }
            SectionNavigationView(module: $app.module)
            ZStack {
                Group {
                    switch app.module ?? .dashboard {
                    case .battery: BatteryView(model: app.battery)
                    case .dashboard: DashboardView(app: app)
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
                    case .uninstall: UninstallView(model: app.uninstall)
                    case .updates: UpdatesView(model: app.updates)
                    case .startup, .privacy, .maintenance, .screenCleaning, .aiClutter, .applicationPermissions, .diskHealth:
                        ToolsDetailPanel(app: app, module: app.module ?? .toolsOverview)
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
