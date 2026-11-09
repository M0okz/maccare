import SwiftUI
import AppKit

struct ApplicationsInsightsManager: View {
    @ObservedObject var app: AppState
    @ObservedObject private var model: ApplicationsInsightsModel
    let category: ApplicationsDetail
    let onBack: () -> Void
    @State private var selectedID: String?
    @State private var confirmTrash = false

    init(app: AppState, category: ApplicationsDetail, onBack: @escaping () -> Void) {
        self.app = app; self.model = app.applicationsInsights; self.category = category; self.onBack = onBack
    }
    private var apps: [ApplicationInsightItem] { category == .unused ? model.snapshot.unused : model.snapshot.incompatible }
    private var selectedApp: ApplicationInsightItem? { apps.first { $0.id == selectedID } ?? apps.first }
    private var selectedInstaller: ScanItem? { model.snapshot.installers.first { $0.id == selectedID } ?? model.snapshot.installers.first }

    var body: some View {
        VStack(spacing: 0) {
            ScreenToolbar(title: category.title) {
                Button(action: onBack) { Label("Retour", systemImage: "chevron.left") }
                    .buttonStyle(ToolbarActionButtonStyle()).keyboardShortcut(.cancelAction).disabled(model.isRemoving)
            } trailing: { EmptyView() }.padding(.horizontal, 24).frame(height: 56)
            Divider()
            HSplitView {
                browser.frame(minWidth: 250, idealWidth: 300, maxWidth: 350)
                inspection.frame(minWidth: 310, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            AdaptiveActionRow {
                Text(model.removalMessage ?? (category == .installers ? "Aucun fichier n’est coché au départ. L’installation peut encore vous être utile." : "Ce résultat est une invitation à examiner l’app. Aucune désinstallation automatique."))
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
            } actions: {
                if category == .installers {
                    Button("Mettre à la Corbeille") { confirmTrash = true }
                        .buttonStyle(.borderedProminent).disabled(model.selectedInstallers.isEmpty || model.isRemoving)
                } else if let item = selectedApp {
                    Button("Examiner la désinstallation") { examine(item.app) }.buttonStyle(.borderedProminent)
                }
            }.padding(18).background(Theme.sidebar)
        }
        .alert("Mettre ces installateurs à la Corbeille ?", isPresented: $confirmTrash) {
            Button("Annuler", role: .cancel) {}
            Button("Mettre à la Corbeille", role: .destructive) { model.trashSelectedInstallers() }
        } message: { Text("\(model.selectedInstallers.count) fichiers sélectionnés. Vérifiez que vous n’en avez plus besoin. Aucune application installée ne sera supprimée.") }
    }
    private var browser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(category.title).font(.headline).accessibilityAddTraits(.isHeader).padding(.bottom, 8)
                if category == .installers {
                    ForEach(model.snapshot.installers) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(item.url.lastPathComponent, isOn: Binding(
                                get: { model.selectedInstallers.contains(item.id) },
                                set: { if $0 { model.selectedInstallers.insert(item.id) } else { model.selectedInstallers.remove(item.id) } }))
                                .disabled(model.isRemoving)
                            Button { selectedID = item.id } label: {
                                Label("\(humanSize(item.size_bytes)) · Détails", systemImage: "doc.text.magnifyingglass")
                                    .font(AppFont.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }.padding(12).background(selectedInstaller?.id == item.id ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                } else {
                    ForEach(apps) { item in
                        Button { selectedID = item.id } label: {
                            HStack(spacing: 12) {
                                AppIcon(app: item.app, size: 32).accessibilityHidden(true)
                                Text(item.app.name).font(AppFont.body).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(12).contentShape(Rectangle())
                                .background(selectedApp?.id == item.id ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).accessibilityAddTraits(selectedApp?.id == item.id ? .isSelected : [])
                    }
                }
            }.padding(18)
        }
    }
    private var inspection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if category == .unused {
                    Text("Comment les apps sont repérées").font(.headline).accessibilityAddTraits(.isHeader)
                    Text("Au moins 30 jours depuis la dernière ouverture enregistrée et 30 jours depuis l’arrivée au même emplacement. Les apps ouvertes, agents et dates inconnues sont exclus. Ce signal n’est pas une preuve d’inutilité.")
                    Text("\(model.snapshot.unknownUsage) applications ont des dates incomplètes et ne sont pas classées comme peu utilisées.").font(AppFont.secondary)
                    Divider()
                }
                if category == .installers, let item = selectedInstaller {
                    Label(item.url.lastPathComponent, systemImage: "shippingbox.fill").font(.title2).accessibilityAddTraits(.isHeader)
                    Text("\(humanSize(item.size_bytes)) · Installateur téléchargé").font(AppFont.body)
                    Text("MacCare ne peut pas déterminer si ce fichier a déjà servi. Le retirer n’est pas nécessaire pour désinstaller l’application.")
                    path(item.url)
                } else if let item = selectedApp {
                    HStack(spacing: 14) { AppIcon(app: item.app, size: 56).accessibilityHidden(true); Text(item.app.name).font(.title2).accessibilityAddTraits(.isHeader) }
                    Text(item.detail).font(AppFont.body)
                    if let date = item.lastUsed {
                        Text("Dernière ouverture enregistrée : \(date.formatted(date: .abbreviated, time: .omitted))").font(AppFont.secondary)
                    }
                    if category == .unused {
                        Text("Seuil : 30 jours sans ouverture enregistrée, avec 30 jours de présence au même emplacement. Apps ouvertes, agents et dates inconnues sont écartés. Les métadonnées Spotlight peuvent être incomplètes ; une activité en arrière-plan peut ne pas y figurer.")
                    } else {
                        Text("Ce contrôle vérifie les architectures déclarées par le binaire principal et les versions minimales de macOS. Il ne détecte pas tous les problèmes d’exécution ou de modules complémentaires. Une app Intel compatible avec Rosetta n’est pas déclarée incompatible pour ce seul motif.")
                    }
                    path(item.app.url)
                } else { Text("Aucun élément à examiner dans cette catégorie.").font(.title2) }
            }.font(AppFont.body).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading).padding(28)
        }
    }
    private func path(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(url.path).font(AppFont.secondary).textSelection(.enabled)
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
    private func examine(_ item: AppInfo) {
        app.uninstall.showingLeftovers = false
        app.uninstall.selectedApp = item
        app.applicationsDetail = .installed
    }
}
