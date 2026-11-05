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

    private var hasResults: Bool { smart.stage == .results || smart.stage == .cleaning }
    private var scanning: Bool { smart.stage == .scanning }
    private var heroDetail: String {
        if scanning { return smart.currentLabel ?? "Recherche des éléments récupérables…" }
        if smart.wasCancelled { return hasResults ? "Des résultats partiels sont disponibles." : "Relancez l’analyse pour connaître l’espace récupérable." }
        return "Caches et journaux régénérables"
    }

    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if permissions.showBanner { permissionBanner }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        hero.frame(minWidth: 390, maxWidth: .infinity)
                        storage.frame(width: 290)
                    }.fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 20) { hero; storage }
                }
                HomeStatusCards(app: app, availableWidth: min(geometry.size.width, 1200) - 56)
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

    @ViewBuilder private var storage: some View {
        if let disk {
            HomeStorageCard(free: disk.free, total: disk.total) { app.select(.space) }
        } else {
            Button { app.select(.space) } label: {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Disque de démarrage", systemImage: "internaldrive").font(.headline)
                    Text("Le stockage n’a pas pu être mesuré.").font(AppFont.body).foregroundStyle(Theme.muted)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(RoundedRectangle(cornerRadius: 22))
            }.buttonStyle(HomeStorageCardStyle()).accessibilityHint("Ouvrir Espace disque")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label(scanning ? "Analyse en cours" : "Bilan du nettoyage", systemImage: "sparkles").font(.headline)
                Spacer()
                if let last = smart.lastCompletedAt, !scanning {
                    ScanAgeText(date: last).font(AppFont.caption).foregroundStyle(Theme.muted)
                }
            }
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(heroMetric).font(.largeTitle.weight(.semibold)).monospacedDigit()
                        .accessibilityAddTraits(.isHeader)
                    Text(heroMetricDetail).font(AppFont.body).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(scanning ? "Suivre" : (hasResults ? "Bilan" : "Analyser")) { openAnalysis() }
                    .buttonStyle(CircularOverviewActionStyle(tint: ModuleColor.clean))
                    .accessibilityLabel(scanning ? "Voir la progression de l’analyse" : (hasResults ? "Voir le bilan du nettoyage" : "Analyser mon Mac"))
            }
            if scanning {
                ProgressView(value: smart.progress).accessibilityLabel("Progression de l’analyse")
                Button("Arrêter l’analyse") { smart.cancelScan() }.buttonStyle(LinkStyle())
            } else if hasResults || smart.wasCancelled {
                Button("Relancer l’analyse") { app.select(.cleaning); smart.scan() }
                    .buttonStyle(LinkStyle()).disabled(smart.stage == .cleaning)
            }
            Text(scanning ? heroDetail : "Analyse seule. Vous choisissez chaque suppression.")
                .font(AppFont.secondary).foregroundStyle(Theme.muted)
        }
        .padding(24).frame(maxWidth: .infinity, minHeight: 245, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [ModuleColor.clean.opacity(0.24), .white.opacity(0.035)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.12)))
    }

    private var heroMetric: String {
        if scanning { return "On fait le point…" }
        if smart.stage == .cleaning { return "Nettoyage en cours" }
        if smart.wasCancelled { return "Analyse interrompue" }
        if smart.isComplete { return humanSize(smart.safeSize) }
        if smart.lastCompletedAt != nil { return humanSize(smart.lastSafeBytes) }
        return "Faites place nette"
    }
    private var heroMetricDetail: String {
        if scanning { return heroDetail }
        if smart.stage == .cleaning { return "Consultez le bilan pour suivre l’opération." }
        if smart.wasCancelled { return heroDetail }
        if smart.isComplete { return "récupérables dans le bilan actuel" }
        if smart.lastCompletedAt != nil { return "repérés lors de la dernière analyse" }
        return "Repérez les caches et journaux régénérables de votre Mac."
    }
    private func openAnalysis() {
        app.select(.cleaning)
        if smart.stage == .idle { smart.scan() }
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
