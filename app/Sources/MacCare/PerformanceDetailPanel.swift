import SwiftUI

struct PerformanceDetailPanel: View {
    @ObservedObject var app: AppState
    @ObservedObject private var tasks: PerformanceTasksModel
    @ObservedObject private var repairs: MaintenanceModel
    @ObservedObject private var startup: StartupModel
    let category: PerformanceCategory
    init(app: AppState, category: PerformanceCategory) {
        self.app = app; tasks = app.performanceTasks; repairs = app.maintenance; startup = app.startup; self.category = category
    }
    private var writing: Bool { tasks.running != nil || repairs.running != nil || startup.busyPath != nil }
    var body: some View {
        VStack(spacing: 0) {
            ScreenToolbar(title: "Gestionnaire Performances") {
                Button { app.performanceDetail = nil } label: { Label("Retour", systemImage: "chevron.left") }
                    .buttonStyle(ToolbarActionButtonStyle()).keyboardShortcut(.cancelAction).disabled(writing)
            } trailing: {
                Picker("Catégorie", selection: Binding(get: { category }, set: { app.performanceDetail = $0 })) {
                    ForEach(PerformanceCategory.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 225).accessibilityLabel("Catégorie de performances").disabled(writing)
            }.padding(.horizontal, 24).frame(height: 56)
            Divider()
            Group {
                switch category {
                case .maintenance: PerformanceMaintenanceView(app: app)
                case .login: PerformanceStartupManager(model: startup, permissions: app.permissions, category: .login)
                case .background: PerformanceStartupManager(model: startup, permissions: app.permissions, category: .background)
                }
            }.id(category).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.modifier(ManagerPanelStyle(accent: ModuleColor.startup))
    }
}
