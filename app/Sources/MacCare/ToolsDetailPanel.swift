import SwiftUI

/// Même cadre que les gestionnaires Applications et Mes fichiers, pour chaque outil.
struct ToolsDetailPanel: View {
    @ObservedObject var app: AppState
    @ObservedObject private var ai: AIClutterModel
    @ObservedObject private var privacy: PrivacyModel
    @ObservedObject private var repairs: MaintenanceModel
    @ObservedObject private var startup: StartupModel
    @State private var startupCategory: PerformanceCategory = .background
    let module: Module

    init(app: AppState, module: Module) {
        self.app = app; self.module = module
        ai = app.aiClutter; privacy = app.privacy; repairs = app.maintenance; startup = app.startup
    }
    private var writing: Bool {
        switch module {
        case .aiClutter: return ai.isCleaning
        case .privacy: return privacy.isCleaning
        case .maintenance: return repairs.running != nil
        case .startup: return startup.busyPath != nil
        default: return false
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            ScreenToolbar(title: "Gestionnaire Outils") {
                Button { app.module = .toolsOverview } label: { Label("Retour", systemImage: "chevron.left") }
                    .buttonStyle(ToolbarActionButtonStyle()).keyboardShortcut(.cancelAction).disabled(writing)
            } trailing: {
                if module == .startup {
                    Picker("Catégorie de démarrage", selection: $startupCategory) {
                        Text("À la connexion").tag(PerformanceCategory.login)
                        Text("En arrière-plan").tag(PerformanceCategory.background)
                    }.labelsHidden().accessibilityLabel("Catégorie de démarrage").frame(width: 200).disabled(writing)
                }
            }.padding(.horizontal, 24).frame(height: 56)
            Divider()
            Group {
                switch module {
                case .diskHealth: DiskHealthView()
                case .aiClutter: AIClutterView(model: ai)
                case .applicationPermissions: ApplicationPermissionsView(model: app.applicationPermissions)
                case .privacy: PrivacyView(model: privacy)
                case .maintenance: MaintenanceView(model: repairs)
                case .startup:
                    PerformanceStartupManager(model: startup, permissions: app.permissions, category: startupCategory,
                                              footerBackground: Color(hex: "#EEECF5")).id(startupCategory)
                case .screenCleaning: ScreenCleaningView(controller: app.screenCleaning)
                default: EmptyView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.modifier(ManagerPanelStyle(accent: Theme.accent, background: NavigationSection.tools.palette.base))
    }
}

struct ToolManagerFooter<Summary: View, Actions: View>: View {
    @ViewBuilder let summary: () -> Summary
    @ViewBuilder let actions: () -> Actions
    var body: some View {
        AdaptiveActionRow(summary: summary, actions: actions)
            .padding(18).background(Color(hex: "#EEECF5"))
    }
}

/// Le panneau est clair même si l'apparence globale de la fenêtre principale est sombre.
struct ToolConfirmationStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.foregroundStyle(Theme.fg).background(Color.white)
            .environment(\.colorScheme, .light).preferredColorScheme(.light).tint(Theme.accent)
    }
}
