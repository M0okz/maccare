import SwiftUI

/// Une entrée par besoin. Aucune analyse ni opération n’est lancée en ouvrant cette page.
struct ToolsOverviewView: View {
    @ObservedObject var app: AppState
    @AppStorage(DeveloperTools.key) private var developerTools = DeveloperTools.defaultValue

    var body: some View {
        ZStack {
            CategoryBackground(section: .tools)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 32) {
                        artwork.frame(width: 170, height: 180)
                        VStack(alignment: .leading, spacing: 14) {
                            Text(NavigationSection.tools.title).font(.system(size: 44, weight: .regular)).accessibilityAddTraits(.isHeader)
                            Text("Un souci à régler ? Choisissez ce dont votre Mac a besoin.")
                                .font(.system(size: 18)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Chaque outil vous guide avant toute modification.")
                                .font(AppFont.secondary).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.top, 12)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 18)], spacing: 18) {
                        tool(title: "Santé des disques", subtitle: "Consultez les alertes matérielles, la température et l’endurance de vos disques. Un diagnostic en lecture seule.", action: "Examiner les disques", module: .diskHealth)
                        tool(title: "Mode nettoyage d’écran", subtitle: "Un écran noir et des saisies bloquées pour nettoyer l’écran, le clavier et le trackpad. Quittez avec ⌘ + Échap.", action: "Ouvrir", module: .screenCleaning)
                        tool(title: "Fichiers IA inutiles", subtitle: "Examinez les caches, les historiques et les modèles locaux de vos outils d’IA. Choisissez ce que vous souhaitez retirer.", action: "Analyser", module: .aiClutter)
                        tool(title: "Autorisations des applications", subtitle: "Retrouvez les accès accordés aux applications : écran, caméra, microphone, fichiers et autres fonctionnalités.", action: "Analyser", module: .applicationPermissions)
                        tool(title: "Réparer l’affichage", subtitle: "Des aperçus incorrects, des polices qui s’affichent mal ou un menu « Ouvrir avec » encombré ?", action: "Voir les réparations", module: .maintenance)
                        tool(title: "Gérer le démarrage", subtitle: "Examinez ce qui se lance à la connexion. Mettez un agent en pause et réactivez-le au besoin.", action: "Examiner le démarrage", module: .startup)
                        tool(title: "Caches et données locales", subtitle: "Examinez les caches des navigateurs, les aperçus et les données enregistrées par macOS.", action: "Analyser les données locales", module: .privacy)
                    }
                    if developerTools {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Pour le développement").font(AppFont.section).accessibilityAddTraits(.isHeader)
                            Text("Retrouvez les analyses spécialisées dans Nettoyage.").font(AppFont.secondary).foregroundStyle(Theme.muted)
                            HStack(spacing: 16) {
                                developerLink("Fichiers de développement", module: .devJunk)
                                developerLink("Simulateurs Xcode", module: .simulators)
                            }
                        }
                    }
                }
                .padding(32).frame(maxWidth: 1060).frame(maxWidth: .infinity)
            }
        }
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36)
                .fill(LinearGradient(colors: [ModuleColor.maint.shade(0.25), Theme.accent.shade(-0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 36).strokeBorder(.white.opacity(0.22)))
                .frame(width: 145, height: 145).rotationEffect(.degrees(-8))
                .shadow(color: ModuleColor.maint.opacity(0.25), radius: 20, y: 10)
            Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 66)).foregroundStyle(.white)
        }.accessibilityHidden(true)
    }

    private func tool(title: String, subtitle: String, action: String, module: Module) -> some View {
        Button {
            app.module = module
            if module == .aiClutter { app.aiClutter.scan() }
            if module == .applicationPermissions { app.applicationPermissions.scan() }
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                ModuleIcon(symbol: module.symbol, color: module.color, size: 48).accessibilityHidden(true)
                Text(title).font(.system(size: 21, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(AppFont.body).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Label(action, systemImage: "arrow.right").font(AppFont.secondary.weight(.semibold)).foregroundStyle(Theme.accentInk)
            }
            .frame(maxWidth: .infinity, minHeight: 250, alignment: .leading).padding(22)
            .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.12)))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain).foregroundStyle(Theme.fg)
        .accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton).accessibilityLabel("\(title). \(subtitle)")
        .accessibilityHint(action)
    }

    private func developerLink(_ title: String, module: Module) -> some View {
        Button { app.module = module } label: {
            Label(title, systemImage: module.symbol).font(AppFont.body)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).foregroundStyle(Theme.accentInk)
    }
}
