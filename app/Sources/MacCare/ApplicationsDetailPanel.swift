import SwiftUI

/// Le bilan reste monté sous le gestionnaire intégré, avec les mêmes modèles.
enum ApplicationsDetail: String, Identifiable {
    case installed, updates, leftovers, startup
    var id: String { rawValue }
    var title: String {
        switch self {
        case .installed: return "Applications installées"
        case .updates: return "Mises à jour"
        case .leftovers: return "Données d’applications supprimées"
        case .startup: return "À l’ouverture du Mac"
        }
    }
}

struct ApplicationsDetailPanel: View {
    @ObservedObject var app: AppState
    @ObservedObject private var uninstall: UninstallModel
    @ObservedObject private var startup: StartupModel
    let detail: ApplicationsDetail

    init(app: AppState, detail: ApplicationsDetail) {
        self.app = app; uninstall = app.uninstall; startup = app.startup; self.detail = detail
    }
    private var writing: Bool {
        switch detail {
        case .installed, .leftovers: return uninstall.isCleaning
        case .startup: return startup.busyPath != nil
        case .updates: return false
        }
    }
    var body: some View {
        Group {
            if detail == .updates {
                ApplicationsUpdatesManager(model: app.updates, apps: uninstall.apps) { close() }
            } else {
                VStack(spacing: 0) {
                    ScreenToolbar(title: "Gestionnaire Applications") {
                        Button { close() } label: { Label("Retour", systemImage: "chevron.left") }
                            .buttonStyle(ToolbarActionButtonStyle()).keyboardShortcut(.cancelAction).disabled(writing)
                    } trailing: { EmptyView() }
                        .padding(.horizontal, 24).frame(height: 56)
                    Divider()
                    Group {
                        switch detail {
                        case .installed, .leftovers: UninstallView(model: uninstall)
                        case .startup: StartupView(model: startup, permissions: app.permissions)
                        case .updates: EmptyView()
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }.modifier(ManagerPanelStyle())
    }
    private func close() { if !writing { app.applicationsDetail = nil } }
}
