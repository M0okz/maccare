import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

// MARK: - Réglages

struct SettingsView: View {
    @ObservedObject var permissions: PermissionsModel
    @ObservedObject var model: ReviewModel
    @ObservedObject var systemClean: SystemCleanModel
    @ObservedObject var updater: AppUpdater
    @AppStorage(DeveloperTools.key) private var developerTools = DeveloperTools.defaultValue
    @AppStorage(ScanScheduler.frequencyKey) private var frequency = ScanScheduler.defaultFrequency.rawValue
    @AppStorage(MenuBarSetting.key) private var menuBarShown = MenuBarSetting.defaultValue
    /// État lu auprès de macOS (jamais un booléen mémorisé par l'app).
    @State private var notificationsDenied = false
    @State private var notificationStatus = "Vérification en cours…"
    @State private var clearExclusionsConfirmation = false
    @Environment(\.scenePhase) private var scenePhase

    @Environment(\.openWindow) private var openWindow
    @State private var tab = SettingsTab.general
    @State private var paneHeights: [SettingsTab: CGFloat] = [:]

    var body: some View {
        TabView(selection: $tab) {
            ForEach(SettingsTab.allCases) { pane in
                ScrollView { settingsPane(pane) }
                .tabItem { Label(pane.title, systemImage: pane.symbol) }
                .tag(pane)
            }
        }
        .frame(width: 860, height: min(paneHeights[tab] ?? 660, 620))
        .background(Color.white)
        .preferredColorScheme(.light)
        .onPreferenceChange(SettingsPaneHeightKey.self) { heights in
            paneHeights.merge(heights) { _, measured in measured }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { refreshStatus() }
        }
        .confirmationDialog("Réintégrer tous les éléments exclus dans les prochaines analyses ?", isPresented: $clearExclusionsConfirmation) {
            Button("Retirer toutes les exclusions", role: .destructive) { model.clearExclusions() }
        } message: {
            Text("Aucun fichier ne sera supprimé. Ces éléments pourront réapparaître dans les résultats.")
        }
    }

    private func settingsPane(_ pane: SettingsTab) -> some View {
        VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(pane.heading).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text(pane.detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if pane == .analysis { AnalysisSettingsView() }
                if pane == .performance { PerformanceSettingsView() }
                if pane == .filesStorage { FileStorageSettingsView() }
                if pane == .general {

                    groupCard("Accès et autorisations") {
                        permissionRow("Accès complet au disque", detail: "Permet d’examiner les emplacements protégés pour un bilan complet.", state: permissions.fullDisk) {
                            permissions.openFullDiskSettings()
                        }
                        Divider().padding(.vertical, 8)
                        permissionRow("Automatisation", detail: "Permet de lire les éléments d’ouverture de session via System Events.", state: permissions.automation) {
                            permissions.openAutomationSettings()
                        }
                        Divider().padding(.vertical, 8)
                        HStack {
                            Text("Les autorisations restent sous votre contrôle dans macOS.").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Actualiser") { refreshStatus() }
                        }
                    }
                    groupCard("Démarrage") {
                        LoginLaunchToggle()
                    }
                    groupCard("Mises à jour de MacCare") {
                        AppUpdateSettingsView(updater: updater)
                    }
                    groupCard("Configuration guidée") {
                        Text("Reprenez les étapes de configuration pour comprendre les accès et le nettoyage système facultatif.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Revoir la configuration de MacCare") {
                            permissions.reopen()
                            openWindow(id: MacCareApp.mainWindowID)
                        }.padding(.top, 6)
                    }

                }
                if pane == .analysis {
                    groupCard("Logs") {
                        HStack {
                            Text("Ignorer les éléments de moins de").font(AppFont.body)
                            Stepper("\(model.logThresholdKB) Kio", value: $model.logThresholdKB, in: 0...10240)
                        }
                    }

                }
                if pane == .protection {
                    groupCard("Suppression") {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Supprimer définitivement (sans corbeille)", isOn: $model.directDelete)
                            .toggleStyle(.switch)
                            if model.directDelete {
                                Label("Irréversible. Les éléments ne passeront pas par la corbeille.",
                                systemImage: "exclamationmark.triangle.fill")
                                .font(AppFont.secondary).foregroundStyle(.orange)
                            }
                        }
                    }

                    groupCard("Nettoyage système") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Assistant privilégié : \(systemClean.statusText).")
                            .font(AppFont.secondary)
                            .foregroundStyle(systemClean.phase == .unavailable || systemClean.phase == .needsApproval ? Color.orange : Color.secondary)
                            Text("Supprime d'anciens journaux de /Library/Logs et /private/var/log, seulement après votre confirmation. Facultatif ; désactivable à tout moment.")
                            .font(AppFont.secondary).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: Space.m) {
                                switch systemClean.phase {
                                    case .off:
                                    Button("Activer") { systemClean.enable() }
                                    case .needsApproval:
                                    Button("Ouvrir les Réglages Système") { systemClean.openApproval() }
                                    case .on:
                                    Button("Désactiver") { systemClean.disable() }
                                    case .unavailable:
                                    EmptyView()
                                }
                            }
                        }
                    }

                }
                if pane == .automation {
                    groupCard("Fréquence des analyses") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Smart Scan automatique", selection: $frequency) {
                                ForEach(ScanFrequency.allCases) { Text($0.title).tag($0.rawValue) }
                            }
                            .pickerStyle(.segmented)
                            // Geste de l'utilisateur : seul moment où l'autorisation de notifier est demandée.
                            .onChange(of: frequency) { value in
                                guard value != ScanFrequency.off.rawValue else { return }
                                ScanScheduler.requestNotificationPermission { granted in notificationsDenied = !granted; refreshStatus() }
                            }
                            Text("Le Smart Scan utilise le profil et les catégories choisis dans Analyse. Les résultats restent à examiner avant tout nettoyage.")
                            .font(AppFont.secondary).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            if notificationsDenied && frequency != ScanFrequency.off.rawValue {
                                Label("Notifications refusées : l'analyse a lieu quand même, son résultat s'affiche dans la barre des menus.",
                                systemImage: "bell.slash").font(AppFont.secondary).foregroundStyle(.orange)
                            }

                        }
                    }

                }
                if pane == .automation {
                    groupCard("Conditions d’exécution") {
                        Label("MacCare doit rester ouvert, dans une fenêtre ou dans la barre des menus.", systemImage: "macwindow")
                        Label("L’accès complet au disque doit être autorisé.", systemImage: "externaldrive")
                        Label("L’analyse attend si vous consultez des résultats ou si la batterie est faible.", systemImage: "pause.circle")
                    }
                    groupCard("Notifications de résultat") {
                        Text(notificationStatus).font(.body.weight(.medium))
                        Text("Une notification indique le total détecté à la fin d’une analyse planifiée. macOS décide de son affichage selon vos réglages et votre mode de concentration.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Ouvrir les réglages de notifications") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                if pane == .menu {
                    groupCard("Barre des menus") {
                        Toggle("Afficher MacCare dans la barre des menus", isOn: $menuBarShown)
                        Text(menuBarShown ? "MacCare reste actif lorsque vous fermez sa fenêtre. Le menu donne accès au dernier bilan et permet de lancer une analyse." : "MacCare quitte lorsque vous fermez sa dernière fenêtre. Les analyses planifiées sont alors interrompues.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    groupCard("Alerte d’espace disque") {
                        StorageAlertSettingsView(menuBarShown: menuBarShown)
                    }
                    groupCard("Alerte de mémoire") {
                        MemoryAlertSettingsView(menuBarShown: menuBarShown)
                    }
                    ForEach(AdditionalAlertKind.allCases) { kind in
                        groupCard(kind.title) {
                            AdditionalAlertSettingsView(kind: kind, menuBarShown: menuBarShown)
                        }
                    }
                    groupCard("Actions disponibles") {
                        Label("Consulter le dernier bilan", systemImage: "chart.bar.doc.horizontal")
                        Label("Lancer un Smart Scan", systemImage: "sparkle.magnifyingglass")
                        Label("Ouvrir la fenêtre de MacCare", systemImage: "macwindow")
                        Text("Le menu ne lance aucune suppression. Examinez les résultats dans la fenêtre principale avant de nettoyer.")
                            .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
                    }
                }
                if pane == .analysis {
                    groupCard("Outils pour développeurs") {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Afficher les catégories pour développeurs", isOn: $developerTools)
                            .toggleStyle(.switch)
                            Text("Xcode (archives, supports d'appareils, documentation), simulateurs et caches d'outils (npm, Cargo, Gradle…). Désactivé, MacCare ne les analyse pas.")
                            .font(AppFont.secondary).foregroundStyle(.secondary)
                        }
                    }

                }
                if pane == .exclusions {
                    Text("Ces exclusions concernent le nettoyage par règles. Les recherches de Mes fichiers conservent leurs exclusions de sûreté intégrées ; elles n’utilisent pas cette liste.")
                        .font(AppFont.secondary).foregroundStyle(.secondary)
                    groupCard("Exclusions personnalisées (\(model.userExclusions.count))") {
                        if model.userExclusions.isEmpty {
                            Text("Aucun élément exclu. Ajoutez un fichier ou un dossier ici, ou utilisez « Exclure définitivement » dans les résultats.")
                            .font(AppFont.secondary).foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(model.userExclusions, id: \.self) { p in
                                    HStack(spacing: 12) {
                                        Image(systemName: "doc.badge.minus").foregroundStyle(.secondary).accessibilityHidden(true)
                                        Text(p).font(.callout).textSelection(.enabled)
                                            .lineLimit(2).truncationMode(.middle).help(p)
                                        Spacer()
                                        Button("Retirer") { model.removeExclusion(p) }
                                            .accessibilityLabel("Retirer l’exclusion de \(p)")
                                    }.padding(.vertical, 6)
                                }
                                Button("Tout retirer…", role: .destructive) { clearExclusionsConfirmation = true }
                                .padding(.top, 4)
                            }
                        }
                    }
                    Button("Ajouter un fichier ou un dossier…") { addExclusion() }
                    Text("Retirer une exclusion ne supprime aucun fichier. Les changements prennent effet à la prochaine analyse.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(30)
            .background(Color.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { refreshStatus() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: SettingsPaneHeightKey.self, value: [pane: geometry.size.height])
                }
            }
    }

    private func refreshStatus() {
        permissions.recheck()
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsDenied = settings.authorizationStatus == .denied
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral: notificationStatus = "Notifications autorisées"
                case .denied: notificationStatus = "Notifications refusées dans macOS"
                case .notDetermined: notificationStatus = "Autorisation demandée à l’activation d’une planification"
                @unknown default: notificationStatus = "État des notifications inconnu"
                }
            }
        }
    }

    private func addExclusion() {
        let panel = NSOpenPanel()
        panel.title = "Exclure des prochaines analyses"
        panel.prompt = "Exclure"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls { model.addExclusion(url.path) }
        }
    }

    private func permissionRow(_ title: String, detail: String, state: PermissionState, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary)
                Text(state == .granted ? "Autorisé" : state == .unknown ? "État à vérifier" : "Non autorisé")
                    .font(.caption.weight(.medium))
            }
            Spacer()
            Button("Ouvrir les réglages", action: action).accessibilityLabel("Ouvrir les réglages : \(title)")
        }
    }

    private func groupCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.m)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
