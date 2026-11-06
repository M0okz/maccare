import SwiftUI

/// Accueil orienté actions : tous les chiffres proviennent des modèles et du disque réel.
struct DashboardView: View {
    @ObservedObject var app: AppState
    @ObservedObject private var smart: SmartScanModel
    @ObservedObject private var permissions: PermissionsModel
    @State private var disk = DiskSpace.current()
    @State private var showingActivity = false

    init(app: AppState) {
        self.app = app
        self.smart = app.smartScan
        self.permissions = app.permissions
    }

    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if permissions.showBanner { permissionBanner }
                hero
                HomeStatusCards(app: app, availableWidth: min(geometry.size.width, 1200) - 56,
                                storage: disk.flatMap { TrayStorageUsage(free: $0.free, total: $0.total) })
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("À vous de choisir").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("Tous les outils") { app.select(.tools) }.buttonStyle(LinkStyle())
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14),
                                             count: geometry.size.width >= 800 ? 4 : 2), spacing: 14) {
                        cleaningShortcut; applicationsShortcut; filesShortcut; performanceShortcut
                    }
                }
                recentActivity
            }.padding(28).frame(maxWidth: 1200).frame(maxWidth: .infinity)
        }
        }
        .onAppear {
            disk = DiskSpace.current()
            if !app.uninstall.leftoversScanned { app.uninstall.scanLeftovers() }
            app.updates.quickCheck()
        }
        .sheet(isPresented: $showingActivity) { ActivityView(app: app) }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Bienvenue dans MacCare").font(.title.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text("Un peu d’entretien. Plus de place pour l’essentiel.").font(AppFont.body).foregroundStyle(Theme.muted)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
    }

    private var hero: some View {
        HomeCleaningCard(model: smart) {
            if smart.stage != .scanning && smart.stage != .cleaning { smart.prepareForNewScan() }
            app.select(.cleaning)
            app.cleaningToolsVisible = false
        }
    }

    private var cleaningShortcut: some View {
        HomeActionCard(title: "Nettoyage", detail: "Caches, journaux et fichiers temporaires.", actionTitle: "Ouvrir le nettoyage", symbol: "sparkles", color: ModuleColor.clean) { app.select(.cleaning) }
    }
    private var applicationsShortcut: some View {
        HomeActionCard(title: "Applications", detail: "Apps installées, résidus et mises à jour.", actionTitle: "Ouvrir les applications", symbol: "app.badge", color: ModuleColor.uninstall) { app.select(.applications) }
    }
    private var filesShortcut: some View {
        HomeActionCard(title: "Mes fichiers", detail: "Gros fichiers et doublons à examiner.", actionTitle: "Ouvrir Mes fichiers", symbol: "folder", color: FilesStyle.accent) { app.select(.files) }
    }
    private var performanceShortcut: some View {
        HomeActionCard(title: "Performances", detail: "Entretien et éléments de démarrage.", actionTitle: "Ouvrir les performances", symbol: "bolt", color: ModuleColor.startup) { app.select(.performance) }
    }

    private var recentActivity: some View {
        HStack(spacing: Space.m) {
            Text("Activité récente").font(AppFont.emphasis)
            if let entry = app.activity.first {
                Image(systemName: "clock").foregroundStyle(Theme.accentInk).accessibilityHidden(true)
                Text(entry.title).font(AppFont.body).foregroundStyle(Theme.muted).lineLimit(1)
            } else {
                Text("Aucune opération terminée dans cette session.").font(AppFont.body).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: Space.s)
            Button("Voir l’activité") { showingActivity = true }.buttonStyle(LinkStyle())
        }
        .padding(Space.l).card()
    }

    private var permissionBanner: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "lock.fill").foregroundStyle(Theme.warn).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Autorisations manquantes").font(AppFont.emphasis)
                Text("\(permissions.missing.joined(separator: " · ")) : certaines analyses sont incomplètes.")
                    .font(AppFont.body).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("Configurer") { permissions.reopen() }.buttonStyle(LinkStyle())
        }
        .padding(Space.l).card()
    }
}
