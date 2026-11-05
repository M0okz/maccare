import SwiftUI

struct StartupView: View {
    @ObservedObject var model: StartupModel
    @ObservedObject var permissions: PermissionsModel
    /// Agent dont la désactivation attend confirmation.
    @State private var confirming: LaunchAgentInfo?
    @State private var filter: StartupFilter
    private let availableFilters: [StartupFilter]
    private let title: String

    init(model: StartupModel, permissions: PermissionsModel, initialFilter: StartupFilter = .all,
         availableFilters: [StartupFilter] = StartupFilter.allCases, title: String = "Démarrage") {
        self.model = model
        self.permissions = permissions
        self._filter = State(initialValue: initialFilter)
        self.availableFilters = availableFilters
        self.title = title
    }
    @State private var search = ""
    @State private var showSystem = false

    /// Les éléments d'ouverture de session passent par System Events : sans l'Automatisation, ils manquent.
    private var loginItemsBlocked: Bool {
        permissions.automation != .granted
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.l) {
                ScreenHeader(
                    title: title,
                    subtitle: availableFilters == [.login]
                        ? "Examinez les applications à la connexion. Pour modifier leur lancement, ouvrez les réglages macOS."
                        : "Choisissez ce qui accompagne l’ouverture de votre session. Les agents désactivés ici peuvent être réactivés à tout moment."
                )
                HStack(spacing: Space.m) {
                    PrimaryButton(title: "Actualiser", systemImage: "arrow.clockwise", tint: ModuleColor.startup) {
                        model.load(includeLoginItems: permissions.automation == .granted)
                    }
                    .disabled(model.isLoading)
                    .opacity(model.isLoading ? 0.5 : 1)
                    Button("Réglages de connexion") { model.openLoginSettings() }
                        .buttonStyle(LinkStyle())
                    Spacer()
                    if model.hasLoaded { Text("\(visibleCount) \(pl(visibleCount, "élément")) \(pl(visibleCount, "affiché"))").font(AppFont.secondary).foregroundStyle(Theme.muted) }
                }
            }
            .padding(Space.xl).padding(.bottom, Space.s)

            content
        }
        .onAppear { if !model.hasLoaded { model.load(includeLoginItems: permissions.automation == .granted) } }
        .sheet(item: $confirming) { confirmation($0) }
        // Une fois l'Automatisation accordée (dans l'app ou dans les Réglages), on relit la liste.
        .onChange(of: permissions.automation) { state in
            if model.hasLoaded { model.load(includeLoginItems: state == .granted) }
        }
    }

    private var automationNotice: some View {
        HStack(spacing: Space.m) {
            ModuleIcon(symbol: "lock.fill", color: Theme.warn, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Éléments d'ouverture de session masqués").font(AppFont.body.weight(.semibold))
                Text("Sans l'Automatisation (System Events), seuls les agents de lancement sont listés.")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            if permissions.automation == .denied {
                PrimaryButton(title: "Ouvrir les Réglages", systemImage: "gearshape.fill", tint: Theme.warn) {
                    permissions.openAutomationSettings()
                }
                .fixedSize()
            } else {
                PrimaryButton(title: permissions.requestingAutomation ? "En attente…" : "Autoriser",
                              systemImage: "hand.tap.fill", tint: Theme.warn) {
                    permissions.requestAutomation()
                }
                .fixedSize()
                .disabled(permissions.requestingAutomation)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .card()
    }

    private var filteredLogins: [StartupItem] { model.loginItems.filter { _ in filter == .all || filter == .login }.filter { StartupFilter.matches(search, values: [$0.name, $0.path]) } }
    private var filteredUsers: [LaunchAgentInfo] { filtered(model.userAgents, category: .agents) }
    private var filteredDisabled: [LaunchAgentInfo] { filtered(model.disabledAgents, category: .disabled) }
    private var filteredSystem: [LaunchAgentInfo] { filtered(model.systemAgents, category: .system) }
    private var visibleCount: Int { filteredLogins.count + filteredUsers.count + filteredDisabled.count + filteredSystem.count }
    private func filtered(_ agents: [LaunchAgentInfo], category: StartupFilter) -> [LaunchAgentInfo] {
        guard filter == .all || filter == category else { return [] }
        return agents.filter { StartupFilter.matches(search, values: [$0.label, $0.program ?? "", $0.path]) }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            Spacer(); ProgressView("Lecture des éléments de démarrage…"); Spacer()
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Picker("Afficher", selection: $filter) {
                        ForEach(availableFilters) { Text($0.title).tag($0) }
                    }.frame(maxWidth: 260)
                    TextField("Rechercher un élément", text: $search).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Rechercher un élément de démarrage")
                }.padding(.horizontal, Space.xl)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if loginItemsBlocked && (filter == .all || filter == .login) { automationNotice }
                        if let message = model.loginItemsError, filter == .all || filter == .login {
                            Label(message, systemImage: "exclamationmark.triangle").font(AppFont.body).foregroundStyle(Theme.warn)
                        }
                        if let message = model.statusMessage {
                            Label(message, systemImage: "exclamationmark.triangle").font(AppFont.body).foregroundStyle(Theme.warn)
                        }
                        if let msg = model.lastAction {
                            Label(msg, systemImage: model.lastActionFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .font(AppFont.secondary).foregroundStyle(model.lastActionFailed ? Theme.warn : Theme.ok)
                        }
                        if !filteredLogins.isEmpty { section("Apps à la connexion", filteredLogins, symbol: "person.crop.circle") }
                        if !filteredUsers.isEmpty { agentSection("Agents de votre session", filteredUsers) }
                        if !filteredDisabled.isEmpty { agentSection("Désactivés par MacCare", filteredDisabled) }
                        if !filteredSystem.isEmpty {
                            if filter == .system || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                agentSection("Agents du système · lecture seule", filteredSystem)
                            } else {
                                DisclosureGroup(isExpanded: $showSystem) {
                                    agentSection("Agents du système · lecture seule", filteredSystem).padding(.top, 12)
                                } label: {
                                    Text("Agents du système · \(filteredSystem.count) · lecture seule").font(AppFont.body.weight(.semibold))
                                }.padding(16).card()
                            }
                        }
                        if visibleCount == 0 {
                            Text(search.isEmpty && filter == .all ? "Aucun élément disponible dans les emplacements accessibles." : "Aucun élément ne correspond à cette recherche.")
                                .font(AppFont.body).foregroundStyle(Theme.muted).padding(.vertical, 32)
                        }
                    }.padding(.horizontal, Space.xl).padding(.bottom, Space.l)
                }
            }
        }
    }

    private func section(_ title: String, _ items: [StartupItem], symbol: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("\(title) · \(items.count)")
                .font(AppFont.section).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    if idx > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    row(item, symbol: symbol)
                }
            }
            .card()
        }
    }

    private func agentSection(_ title: String, _ agents: [LaunchAgentInfo]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("\(title) · \(agents.count)")
                .font(AppFont.section).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(agents.enumerated()), id: \.element.id) { idx, agent in
                    if idx > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    agentRow(agent)
                }
            }
            .card()
        }
    }

    private func agentRow(_ a: LaunchAgentInfo) -> some View {
        HStack(spacing: 11) {
            ModuleIcon(symbol: a.scope == "system" ? "lock.fill" : (a.scope == "disabled" ? "pause.circle.fill" : "gearshape.2"),
                       color: a.scope == "disabled" ? Theme.faint : ModuleColor.startup, size: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.label).font(AppFont.body.weight(.semibold)).lineLimit(1).help(a.label)
                DisclosureGroup("Détails techniques") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(a.path).textSelection(.enabled)
                        if let program = a.program { Text(program).textSelection(.enabled) }
                    }.font(AppFont.caption).foregroundStyle(Theme.muted).padding(.top, 6)
                }.font(AppFont.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            if a.orphan { PillBadge(text: "App introuvable", kind: .review) }
            if let tool = a.managed_by { PillBadge(text: tool, kind: .safe) }
            if a.scope == "user" {
                PillBadge(text: !a.state_known ? "État inconnu" : (a.running ? "En cours" : "Au repos"), kind: a.state_known ? .safe : .review)
            }
            if model.busyPath == a.path {
                ProgressView().controlSize(.small)
            } else if a.scope == "disabled" {
                Button("Réactiver") { model.toggle(a) }.buttonStyle(LinkStyle()).font(AppFont.secondary).disabled(model.busyPath != nil)
            } else if a.canDisable {
                Button("Désactiver") { confirming = a }.buttonStyle(LinkStyle()).font(AppFont.secondary)
                    .disabled(model.busyPath != nil)
            }
            if a.scope != "disabled" {
                Button("Emplacement") { model.reveal(a) }.buttonStyle(LinkStyle()).font(AppFont.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// Confirmation de désactivation : nomme l'agent, dit s'il tourne et qui le gère.
    /// « Annuler » est l'action par défaut.
    private func confirmation(_ a: LaunchAgentInfo) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Désactiver « \(a.label) » ?").font(AppFont.emphasis.weight(.bold))
            if a.running {
                Text("Il est en cours d'exécution : il sera arrêté maintenant et ne se relancera plus à l'ouverture de session.")
                    .font(AppFont.body).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Il ne se lancera plus à l'ouverture de session.")
                    .font(AppFont.body)
            }
            if a.orphan {
                Text("Son programme est introuvable : l'app qui l'a installé a probablement été supprimée.")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            if let tool = a.managed_by {
                Text("Cet agent est géré par \(tool) : l'outil peut le réactiver ou se désynchroniser (préférez « brew services stop » pour un service Homebrew).")
                    .font(AppFont.secondary).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
            }
            Text("Réversible : MacCare le met de côté et peut le réactiver depuis cet écran.")
                .font(AppFont.secondary).foregroundStyle(Theme.muted)
            HStack {
                Spacer()
                Button("Annuler") { confirming = nil }.keyboardShortcut(.defaultAction)
                Button("Désactiver") {
                    confirming = nil
                    model.toggle(a)
                }
            }
        }
        .padding(Space.xl)
        .frame(width: 460)
        .onExitCommand { confirming = nil }
    }

    private func row(_ item: StartupItem, symbol: String) -> some View {
        HStack(spacing: 11) {
            ModuleIcon(symbol: symbol, color: ModuleColor.startup, size: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(AppFont.body.weight(.semibold))
                Text(item.detail.isEmpty ? item.path : item.detail)
                    .font(AppFont.caption).foregroundStyle(Theme.faint)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if item.hasFile {
                Button("Emplacement") { model.reveal(item) }.buttonStyle(LinkStyle()).font(AppFont.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
