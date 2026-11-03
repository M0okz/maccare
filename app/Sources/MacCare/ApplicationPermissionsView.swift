import SwiftUI
import AppKit

struct ApplicationPermissionsView: View {
    @ObservedObject var model: ApplicationPermissionsModel
    @State private var service = ""
    @State private var query = ""
    @State private var grantedOnly = true
    @State private var confirming = false
    @State private var showReadDetails = false

    private var entries: [ApplicationPermission] { model.snapshot.entries.filter { !grantedOnly || $0.granted } }
    private var services: [String] { Set(entries.map(\.service)).sorted { title($0).localizedStandardCompare(title($1)) == .orderedAscending } }
    private var appearance: ApplicationPermissionAppearance { .init(service: service) }
    private var visible: [ApplicationPermission] {
        entries.filter {
            (service.isEmpty || $0.service == service) && (query.isEmpty ||
                model.name(for: $0).localizedStandardContains(query) || $0.client.localizedStandardContains(query))
        }.sorted { model.name(for: $0).localizedStandardCompare(model.name(for: $1)) == .orderedAscending }
    }
    private var pane: String { ApplicationPermissionStore.services[service]?.pane ?? "Privacy" }

    var body: some View {
        VStack(spacing: 0) {
            if model.busy {
                Spacer(); ProgressView("Lecture des autorisations…"); Spacer()
            } else {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        browser.frame(width: max(240, min(310, geometry.size.width * 0.28)))
                        Divider()
                        inspection
                    }
                }
            }
            Divider()
            footer
        }
        .onAppear { if !model.hasScanned { model.scan() } }
        .onChange(of: grantedOnly) { _ in service = ""; model.selection = [] }
        .sheet(isPresented: $confirming) { confirmation.modifier(ToolConfirmationStyle()) }
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Autorisations des applications").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
            Text("Examinez les accès aux fonctionnalités de votre Mac.").font(AppFont.secondary).foregroundStyle(Theme.muted)
            HStack {
                Text("\(entries.count) accès").font(AppFont.secondary).monospacedDigit()
                Spacer()
                Button { model.scan() } label: { Image(systemName: "arrow.clockwise").frame(width: 32, height: 32) }
                    .buttonStyle(.plain).disabled(model.busy).accessibilityLabel("Actualiser les autorisations")
            }
            ScrollView {
                VStack(spacing: 7) {
                    category("", label: "Tous les accès", count: entries.count)
                    ForEach(services, id: \.self) { value in
                        category(value, label: title(value), count: entries.filter { $0.service == value }.count)
                    }
                }
            }
            Toggle("Autorisés uniquement", isOn: $grantedOnly).font(AppFont.secondary).padding(.horizontal, 8)
        }.padding(20)
    }

    private var inspection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                ModuleIcon(symbol: appearance.symbol, color: appearance.color, size: 52).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(service.isEmpty ? "Tous les accès" : title(service)).font(AppFont.metric).accessibilityAddTraits(.isHeader)
                    Text(appearance.detail).font(AppFont.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
            }.padding(.bottom, 22)
            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted).accessibilityHidden(true)
                    TextField("Rechercher une application", text: $query).textFieldStyle(.plain)
                }.padding(11).background(Color(hex: "#F4F2F8"), in: RoundedRectangle(cornerRadius: 10))
                Text("\(visible.count) accès").font(AppFont.secondary).foregroundStyle(Theme.muted).monospacedDigit()
            }.padding(.bottom, 16)
            if !model.snapshot.warnings.isEmpty { readWarning.padding(.bottom, 14) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if visible.isEmpty && model.snapshot.readableDatabases > 0 {
                        VStack(spacing: 14) {
                            Image(systemName: "checkmark.shield").font(.system(size: 42)).foregroundStyle(Theme.muted).accessibilityHidden(true)
                            Text("Aucun accès à afficher").font(AppFont.emphasis)
                            Text("Essayez une autre catégorie ou modifiez les filtres.").foregroundStyle(Theme.muted)
                        }.frame(maxWidth: .infinity).padding(.vertical, 48)
                    }
                    ForEach(visible) { entry in
                        permissionRow(entry)
                        Divider().padding(.leading, entry.canReset ? 88 : 64)
                    }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").accessibilityHidden(true)
                Text("Les accès système se gèrent dans macOS. Les accès utilisateur sélectionnables peuvent être réinitialisés ici.")
                    .fixedSize(horizontal: false, vertical: true)
            }.font(AppFont.secondary).foregroundStyle(Theme.muted).padding(.top, 16)
        }.padding(26).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var readWarning: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
                Text(model.snapshot.readableDatabases == 0 ? "Lecture indisponible" : "Certains accès ne sont pas lisibles").font(AppFont.secondary.weight(.semibold))
                Spacer()
                Button("Détails") { showReadDetails.toggle() }.buttonStyle(.plain).foregroundStyle(Theme.accentInk)
            }
            if showReadDetails {
                ForEach(model.snapshot.warnings, id: \.self) { Text($0).font(AppFont.secondary).fixedSize(horizontal: false, vertical: true) }
                Button("Vérifier l’accès au disque") { model.openSettings("Privacy_AllFiles") }.buttonStyle(SecondaryActionButtonStyle())
            }
        }.padding(14).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
    }

    private func permissionRow(_ entry: ApplicationPermission) -> some View {
        HStack(spacing: 16) {
            if entry.canReset {
                Toggle("Sélectionner \(model.name(for: entry)) pour \(entry.title)", isOn: Binding(get: { model.selection.contains(entry.id) }, set: { value in
                    if value { model.selection.insert(entry.id) } else { model.selection.remove(entry.id) }
                })).toggleStyle(.checkbox).labelsHidden()
            }
            applicationIcon(entry).frame(width: 46, height: 46).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.name(for: entry)).font(AppFont.emphasis)
                HStack(spacing: 6) {
                    Image(systemName: entry.granted ? "checkmark.circle.fill" : "minus.circle.fill")
                        .foregroundStyle(entry.granted ? Color(hex: "#258657") : Theme.muted).accessibilityHidden(true)
                    Text(entry.state + (service.isEmpty ? " · \(entry.title)" : ""))
                        .foregroundStyle(Theme.muted)
                }.font(AppFont.secondary)
                if entry.managed { Text("Gérée par une organisation").font(AppFont.caption).foregroundStyle(Theme.muted) }
                if entry.service == "kTCCServiceAppleEvents" && entry.target != "UNUSED" && !entry.target.isEmpty {
                    Text("Vers \(AppNames.name(for: entry.target))").font(AppFont.secondary).foregroundStyle(Theme.muted)
                }
            }.help(entry.client)
            Spacer(minLength: 8)
            Button { model.openSettings(entry.settingsPane) } label: {
                Label("Gérer", systemImage: "slider.horizontal.3")
            }.buttonStyle(SecondaryActionButtonStyle()).help("Ouvrir \(entry.title) dans les Réglages Système")
        }.padding(.vertical, 18)
    }

    @ViewBuilder private func applicationIcon(_ entry: ApplicationPermission) -> some View {
        if let url = entry.clientType == 1 ? URL(fileURLWithPath: entry.client) : NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.client) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
        } else {
            ModuleIcon(symbol: "app.fill", color: .purple, size: 44)
        }
    }

    private func category(_ key: String, label: String, count: Int) -> some View {
        let style = ApplicationPermissionAppearance(service: key)
        return Button { service = key } label: {
            HStack(spacing: 11) {
                ModuleIcon(symbol: style.symbol, color: style.color, size: 30).accessibilityHidden(true)
                Text(label).font(AppFont.body.weight(service == key ? .semibold : .regular)).multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Text("\(count)").font(AppFont.secondary).monospacedDigit().foregroundStyle(Theme.muted)
            }.padding(.horizontal, 12).padding(.vertical, 13)
                .background(service == key ? ModuleColor.privacy.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityAddTraits(service == key ? .isSelected : [])
    }
    private var footer: some View {
        ToolManagerFooter {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Image(systemName: model.chosen.isEmpty ? "lock.shield" : "checkmark.circle.fill").foregroundStyle(ModuleColor.privacy).accessibilityHidden(true)
                    Text(model.chosen.isEmpty ? "Vous choisissez les accès à conserver" : "\(model.chosen.count) accès sélectionné(s)")
                        .font(AppFont.body.weight(.semibold))
                }
                if let message = model.message { Text(message).font(AppFont.secondary).foregroundStyle(Theme.muted) }
            }
        } actions: {
            if model.chosen.isEmpty {
                Button("Ouvrir les réglages macOS", systemImage: "arrow.up.forward") { model.openSettings(pane) }
                    .buttonStyle(.borderedProminent).disabled(model.busy)
            } else {
                Button("Réinitialiser la sélection…") { confirming = true }
                    .buttonStyle(.borderedProminent).disabled(model.busy)
            }
        }
    }
    private func title(_ key: String) -> String { ApplicationPermissionStore.services[key]?.title ?? key.replacingOccurrences(of: "kTCCService", with: "") }
    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Réinitialiser ces autorisations ?").font(AppFont.section).accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.chosen) { entry in Text("\(model.name(for: entry)) · \(entry.title)") }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 160)
            Text("Quittez les applications concernées avant de continuer. Leur autorisation actuelle sera effacée. Elles pourront afficher une nouvelle demande d’accès à la prochaine utilisation.")
            HStack {
                Spacer()
                Button("Annuler") { confirming = false }.keyboardShortcut(.cancelAction)
                Button("Réinitialiser", role: .destructive) { confirming = false; model.resetSelected() }
            }
        }.font(AppFont.body).padding(28).frame(width: 540)
    }
}
