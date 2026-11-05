import SwiftUI

struct CleaningDetailPanel: View {
    @ObservedObject var app: AppState
    @ObservedObject private var smart: SmartScanModel
    @ObservedObject private var review: ReviewModel
    @ObservedObject private var trash: TrashModel
    @ObservedObject private var system: SystemCleanModel
    @ObservedObject private var development: DevJunkModel
    @ObservedObject private var simulators: SimulatorsModel
    @AppStorage(DeveloperTools.key) private var developerTools = DeveloperTools.defaultValue
    let module: Module

    init(app: AppState, module: Module) {
        self.app = app; self.module = module
        smart = app.smartScan; review = app.review; trash = app.trash
        system = app.systemClean; development = app.devJunk; simulators = app.simulators
    }

    private var busy: Bool {
        smart.stage == .scanning || smart.stage == .cleaning || review.isScanning || review.isCleaning
            || trash.isLoading || trash.isEmptying || system.isLoading || system.isRemoving
            || development.isScanning || development.isCleaning || simulators.isLoading || simulators.isDeleting
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenToolbar(title: "Gestionnaire Nettoyage") {
                Button { app.module = .cleaningOverview } label: { Label("Retour", systemImage: "chevron.left") }
                    .buttonStyle(ToolbarActionButtonStyle()).keyboardShortcut(.cancelAction).disabled(busy)
            } trailing: {
                Picker("Outil de nettoyage", selection: Binding(get: { module }, set: { app.module = $0 })) {
                    ForEach(NavigationSection.cleaning.destinations(developerTools: developerTools).filter { $0 != .cleaningOverview }) {
                        Text($0.tabTitle).tag($0)
                    }
                }.labelsHidden().frame(width: 225).accessibilityLabel("Outil de nettoyage").disabled(busy)
            }.padding(.horizontal, 24).frame(height: 56)
            Divider()
            Group {
                switch module {
                case .smartScan: SmartScanView(model: smart)
                case .cleaning: CleaningView(model: review)
                case .trash: TrashView(model: trash, permissions: app.permissions)
                case .systemClean: SystemCleanView(model: system)
                case .devJunk: DevJunkView(model: development)
                case .simulators: SimulatorsView(model: simulators)
                default: EmptyView()
                }
            }.id(module).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .modifier(ManagerPanelStyle(accent: ModuleColor.clean, background: NavigationSection.cleaning.palette.base))
        .onChange(of: developerTools) { enabled in
            if !enabled && module.isDeveloper && !busy { app.module = .cleaning }
        }
    }
}
