import SwiftUI
import AppKit

/// Même lecture en deux colonnes que le gestionnaire Applications ; les mutations restent dans StartupModel.
struct PerformanceStartupManager: View {
    @ObservedObject var model: StartupModel
    @ObservedObject var permissions: PermissionsModel
    let category: PerformanceCategory
    var footerBackground: Color = Theme.sidebar
    @State private var query = ""
    @State private var filter: StartupFilter = .agents
    @State private var selectedID: String?
    @State private var confirming: LaunchAgentInfo?
    @ScaledMetric(relativeTo: .title) private var detailTitleSize: CGFloat = 24

    private var login: Bool { category == .login }
    private var logins: [StartupItem] { model.loginItems.filter { StartupFilter.matches(query, values: [$0.name, $0.path]) } }
    private var agents: [LaunchAgentInfo] {
        let input: [LaunchAgentInfo]
        switch filter {
        case .disabled: input = model.disabledAgents
        case .system: input = model.systemAgents
        default: input = model.userAgents
        }
        return input.filter { StartupFilter.matches(query, values: [$0.label, $0.path, $0.program ?? ""]) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
    private var selectedAgent: LaunchAgentInfo? { agents.first { $0.id == selectedID } ?? agents.first }
    private var selectedLogin: StartupItem? { logins.first { $0.id == selectedID } ?? logins.first }
    private var count: Int { login ? logins.count : agents.count }
    private var countLabel: String {
        if model.isLoading { return "Lecture en cours…" }
        if login && permissions.automation != .granted { return "Accès nécessaire" }
        if login && (!model.loginItemsLoaded || model.loginItemsError != nil) { return "Liste indisponible" }
        return "\(count) \(pl(count, "élément"))"
    }
    private var busy: Bool { model.isLoading || model.busyPath != nil }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    browser.frame(width: max(240, min(310, geometry.size.width * 0.28)))
                    Divider()
                    inspection.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            footer
        }
        .onAppear { if !model.hasLoaded { reload() } }
        .onChange(of: permissions.automation) { _ in if model.hasLoaded { reload() } }
        .sheet(item: $confirming) { confirmation($0).modifier(ToolConfirmationStyle()) }
    }
    private var browser: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(login ? "À la connexion" : "En arrière-plan").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
            Text(login ? "Examinez les apps qui s’ouvrent avec votre session." : "Choisissez un agent pour comprendre son rôle et son état.")
                .font(AppFont.secondary).foregroundStyle(Theme.muted)
            TextField("Rechercher un élément", text: $query).textFieldStyle(.roundedBorder).accessibilityLabel("Rechercher un élément de démarrage")
            if !login {
                Picker("Afficher", selection: $filter) {
                    ForEach([StartupFilter.agents, .disabled, .system]) { Text($0.title).tag($0) }
                }.labelsHidden().accessibilityLabel("Type d’agent")
            }
            HStack {
                Text(countLabel).font(AppFont.secondary).monospacedDigit()
                Spacer()
                Button(action: reload) { Image(systemName: "arrow.clockwise").frame(width: 32, height: 32) }
                    .buttonStyle(.plain).disabled(busy).accessibilityLabel("Actualiser les éléments de démarrage")
            }
            ScrollView {
                LazyVStack(spacing: 5) {
                    if login {
                        ForEach(logins) { item in
                            Button { selectedID = item.id } label: {
                                HStack(spacing: 10) {
                                    if item.hasFile { Image(nsImage: NSWorkspace.shared.icon(forFile: item.path)).resizable().scaledToFit().frame(width: 30, height: 30).accessibilityHidden(true) }
                                    else { Image(systemName: "app").frame(width: 30).accessibilityHidden(true) }
                                    Text(item.name).font(AppFont.body.weight(.medium)).lineLimit(2)
                                    Spacer(minLength: 0)
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(selectedLogin?.id == item.id ? Theme.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain).accessibilityAddTraits(selectedLogin?.id == item.id ? .isSelected : [])
                        }
                    } else {
                        ForEach(agents) { agent in
                            Button { selectedID = agent.id } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: agent.scope == "system" ? "lock.shield" : "gearshape.2").foregroundStyle(ModuleColor.startup).frame(width: 24).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(agent.label).font(AppFont.body.weight(.medium)).lineLimit(2).truncationMode(.middle)
                                        Text(agentState(agent)).font(AppFont.secondary).foregroundStyle(Theme.muted)
                                    }
                                    Spacer(minLength: 0)
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(selectedAgent?.id == agent.id ? Theme.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain).accessibilityAddTraits(selectedAgent?.id == agent.id ? .isSelected : [])
                        }
                    }
                }
            }
        }.padding(20)
    }
    private var inspection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let message = model.statusMessage {
                    Label(message, systemImage: "exclamationmark.triangle").font(AppFont.body).foregroundStyle(Theme.warn)
                }
                if login && permissions.automation != .granted {
                    accessNotice
                } else if login, let error = model.loginItemsError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warn)
                    Button("Ouvrir les réglages d’Automatisation") { permissions.openAutomationSettings() }.buttonStyle(SecondaryActionButtonStyle())
                } else if login, let item = selectedLogin {
                    Text(item.name).font(.system(size: detailTitleSize, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Label("Application à la connexion", systemImage: "power").font(AppFont.body)
                    Text("Cette application accompagne l’ouverture de votre session. Son lancement se règle dans macOS.").font(AppFont.body).foregroundStyle(Theme.muted)
                    Text(item.path.isEmpty ? "Chemin indisponible" : item.path).font(AppFont.secondary).textSelection(.enabled)
                } else if !login, let agent = selectedAgent {
                    Text(agent.label).font(.system(size: detailTitleSize, weight: .semibold)).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    Label(agentState(agent), systemImage: agent.scope == "system" ? "lock.shield" : (agent.running ? "play.circle" : "pause.circle"))
                        .font(AppFont.body.weight(.medium))
                    if agent.scope == "system" {
                        Text("Cet agent appartient au système. Vous pouvez consulter ses informations ; sa modification reste protégée.")
                            .font(AppFont.body).foregroundStyle(Theme.muted)
                    } else if agent.scope == "disabled" {
                        Text("MacCare a mis cet agent de côté. Vous pouvez le réactiver pour retrouver son fonctionnement précédent.")
                            .font(AppFont.body).foregroundStyle(Theme.muted)
                    } else {
                        Text("Cet agent peut exécuter une tâche à l’ouverture de session ou lorsque macOS le sollicite. Au repos ne signifie pas désactivé.")
                            .font(AppFont.body).foregroundStyle(Theme.muted)
                    }
                    if agent.orphan { Label("Son programme est introuvable. L’application correspondante a peut-être été supprimée.", systemImage: "exclamationmark.triangle").font(AppFont.body) }
                    if let tool = agent.managed_by {
                        Label("Géré par \(tool)", systemImage: "wrench.and.screwdriver").font(AppFont.body)
                        Text("Ce gestionnaire peut le réactiver. Pour un service Homebrew, préférez son mécanisme d’arrêt.").font(AppFont.secondary).foregroundStyle(Theme.muted)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Détails techniques").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                        Text(agent.path).font(AppFont.secondary).textSelection(.enabled)
                        if let program = agent.program { Text(program).font(AppFont.secondary).foregroundStyle(Theme.muted).textSelection(.enabled) }
                    }
                } else {
                    Text(model.isLoading ? "Lecture des éléments de démarrage…" : (query.isEmpty ? "Aucun élément disponible dans cette catégorie." : "Aucun élément ne correspond à cette recherche."))
                        .font(AppFont.body).foregroundStyle(Theme.muted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
        }
    }
    private var accessNotice: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Accès aux apps à la connexion", systemImage: "lock").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text("L’Automatisation de System Events permet de lire cette liste. Les agents d’arrière-plan restent consultables séparément.")
                .font(AppFont.body).foregroundStyle(Theme.muted)
            if permissions.automation == .denied {
                Button("Ouvrir les réglages d’Automatisation") { permissions.openAutomationSettings() }.buttonStyle(SecondaryActionButtonStyle())
            } else {
                Button(permissions.requestingAutomation ? "En attente…" : "Autoriser la lecture…") { permissions.requestAutomation() }
                    .buttonStyle(SecondaryActionButtonStyle()).disabled(permissions.requestingAutomation)
            }
        }
    }
    private var footer: some View {
        AdaptiveActionRow {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.busyPath != nil ? "Modification en cours…" : (login ? "Applications à la connexion" : (filter == .system ? "Agents système · lecture seule" : "Gestion réversible des agents")))
                    .font(AppFont.body.weight(.semibold))
                Text(model.lastAction ?? (login ? "Les changements de lancement se font dans les réglages macOS." : (filter == .system ? "Ces agents peuvent être examinés sans être modifiés." : "La désactivation reste soumise à confirmation.")))
                    .font(AppFont.secondary).foregroundStyle(model.lastActionFailed ? Theme.warn : Theme.muted)
            }
        } actions: {
            HStack(spacing: 10) {
                if login {
                    if let item = selectedLogin, item.hasFile { Button("Emplacement") { model.reveal(item) }.buttonStyle(SecondaryActionButtonStyle()) }
                    Button("Réglages de connexion") { model.openLoginSettings() }.buttonStyle(.borderedProminent)
                } else if let agent = selectedAgent {
                    if agent.scope != "disabled" { Button("Emplacement") { model.reveal(agent) }.buttonStyle(SecondaryActionButtonStyle()) }
                    if agent.scope == "disabled" {
                        Button("Réactiver") { model.toggle(agent) }.buttonStyle(.borderedProminent).disabled(busy)
                    } else if agent.canDisable {
                        Button("Désactiver…") { confirming = agent }.buttonStyle(.borderedProminent).disabled(busy)
                    }
                }
            }
        }.padding(18).background(footerBackground)
    }
    private func agentState(_ agent: LaunchAgentInfo) -> String {
        if agent.scope == "system" { return "Système · lecture seule" }
        if agent.scope == "disabled" { return "Désactivé par MacCare" }
        if !agent.state_known { return "État inconnu" }
        return agent.running ? "En cours" : "Au repos"
    }
    private func reload() { model.load(includeLoginItems: permissions.automation == .granted) }

    private func confirmation(_ agent: LaunchAgentInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Désactiver « \(agent.label) » ?").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
            Text(agent.running ? "Il est en cours d’exécution : il sera arrêté maintenant et ne se relancera plus à l’ouverture de session." : "Il ne se lancera plus à l’ouverture de session.")
                .font(AppFont.body).fixedSize(horizontal: false, vertical: true)
            if agent.orphan { Text("Son programme est introuvable : l’application qui l’a installé a probablement été supprimée.").font(AppFont.secondary).foregroundStyle(Theme.muted) }
            if let tool = agent.managed_by { Text("Cet agent est géré par \(tool) : cet outil peut le réactiver. Préférez « brew services stop » pour un service Homebrew.").font(AppFont.body).foregroundStyle(Theme.warn) }
            Text("Réversible : MacCare le met de côté et peut le réactiver depuis cet écran.").font(AppFont.secondary).foregroundStyle(Theme.muted)
            HStack {
                Spacer()
                Button("Annuler") { confirming = nil }.keyboardShortcut(.defaultAction)
                Button("Désactiver") { confirming = nil; model.toggle(agent) }
            }
        }.padding(24).frame(width: 480).onExitCommand { confirming = nil }
    }
}
