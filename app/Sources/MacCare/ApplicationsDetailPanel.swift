import SwiftUI

/// Le bilan reste monté sous le gestionnaire intégré, avec les mêmes modèles.
enum ApplicationsDetail: String, Identifiable {
    case installed, updates, leftovers, startup, unused, incompatible, installers
    var id: String { rawValue }
    var title: String {
        switch self {
        case .installed: return "Applications installées"
        case .updates: return "Mises à jour"
        case .leftovers: return "Données d’applications supprimées"
        case .startup: return "À l’ouverture du Mac"
        case .unused: return "Applications peu utilisées"
        case .incompatible: return "Applications incompatibles"
        case .installers: return "Fichiers d’installation"
        }
    }
}

struct ApplicationsDetailPanel: View {
    @ObservedObject var app: AppState
    @ObservedObject private var uninstall: UninstallModel
    @ObservedObject private var startup: StartupModel
    @State private var startupCategory: PerformanceCategory = .login
    let layout: MainWindowLayout
    let detail: ApplicationsDetail
    var includeAllUpdateSources = false
    var onBack: (() -> Void)?

    init(app: AppState, layout: MainWindowLayout, detail: ApplicationsDetail, includeAllUpdateSources: Bool = false, onBack: (() -> Void)? = nil) {
        self.layout = layout
        self.app = app; uninstall = app.uninstall; startup = app.startup; self.detail = detail
        self.includeAllUpdateSources = includeAllUpdateSources; self.onBack = onBack
    }
    private var writing: Bool {
        switch detail {
        case .installed, .leftovers: return uninstall.isCleaning
        case .startup: return startup.busyPath != nil
        case .updates: return false
        case .unused, .incompatible, .installers: return app.applicationsInsights.isRemoving
        }
    }
    var body: some View {
        Group {
            if detail == .updates && !includeAllUpdateSources {
                ApplicationsUpdatesManager(model: app.updates, installer: app.applicationUpdateInstaller, apps: uninstall.apps) { close() }
                    .modifier(DisplayAdjustedContent(layout: layout))
            } else if [.unused, .incompatible, .installers].contains(detail) {
                ApplicationsInsightsManager(app: app, layout: layout, category: detail, onBack: close)
            } else {
                VStack(spacing: 0) {
                    ScreenToolbar(title: "Gestionnaire Applications") {
                        Button { close() } label: { Label("Retour", systemImage: "chevron.left") }
                            .buttonStyle(.toolbarPill).keyboardShortcut(.cancelAction).disabled(writing)
                    } trailing: {
                        if detail == .startup {
                            Picker("Catégorie de démarrage", selection: $startupCategory) {
                                Text("À la connexion").tag(PerformanceCategory.login)
                                Text("En arrière-plan").tag(PerformanceCategory.background)
                            }.actionCursor().labelsHidden().accessibilityLabel("Catégorie de démarrage").frame(width: 225).disabled(writing)
                        }
                    }
                        .padding(.horizontal, 24).frame(height: 56)
                        .displayScaledBlock(layout.scale)
                    Divider()
                    Group {
                        switch detail {
                        case .installed, .leftovers: UninstallView(model: uninstall, permissions: app.permissions, layout: layout)
                        case .startup:
                            PerformanceStartupManager(model: startup, permissions: app.permissions, category: startupCategory)
                                .id(startupCategory)
                                .modifier(DisplayAdjustedContent(layout: layout))
                        case .updates: UpdatesView(model: app.updates).modifier(DisplayAdjustedContent(layout: layout))
                        case .unused, .incompatible, .installers: EmptyView()
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }.modifier(ManagerPanelStyle())
    }
    private func close() {
        guard !writing else { return }
        if let onBack { onBack() }
        else { app.applicationsDetail = nil }
    }
}
