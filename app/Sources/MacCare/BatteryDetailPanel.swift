import SwiftUI
import MacCareBattery

/// Cadre intégré commun aux gestionnaires : retour, navigateur, détail et actions fixes.
struct BatteryDetailPanel: View {
    @ObservedObject var model: BatteryModel
    @Binding var category: BatteryCategory?
    let selected: BatteryCategory
    @State private var showingDiagnostics = false
    @State private var diagnostics = "Lecture du diagnostic…"
    @State private var confirmingActivation = false
    @AccessibilityFocusState private var errorFocused: Bool
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScreenToolbar(title: "Gestionnaire Batterie") {
                Button { category = nil } label: { Label("Retour", systemImage: "chevron.left") }
                    .buttonStyle(ToolbarActionButtonStyle()).keyboardShortcut(.cancelAction)
            } trailing: { EmptyView() }
                .padding(.horizontal, 24).frame(height: 56)
            Divider()
            ManagerBrowserLayout {
                browser
            } detail: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ScreenHeader(title: selected.title, subtitle: selected.subtitle)
                            .accessibilityFocused($headingFocused)
                        detail
                        if let error = model.error {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                                .accessibilityFocused($errorFocused)
                        }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }.id(selected)
            } footer: {
                footer
            }
        }
        .modifier(ManagerPanelStyle(accent: Theme.ok, background: NavigationSection.battery.palette.base))
        .disabled(model.isTerminating)
        .sheet(isPresented: $showingDiagnostics) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Diagnostic de compatibilité").font(.headline)
                Text("Lecture seule des contrôles de batterie. Aucun réglage de charge n’est modifié.").font(.callout)
                ScrollView { Text(diagnostics).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Button("Fermer") { showingDiagnostics = false }.keyboardShortcut(.cancelAction)
            }.padding(24).frame(width: 700, height: 480).modifier(ManagerSheetStyle())
        }
        .onChange(of: model.error) { errorFocused = $0 != nil }
        .onAppear { headingFocused = true }
        .onChange(of: selected) { _ in headingFocused = true }
    }
    private var browser: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Batterie").font(AppFont.section).accessibilityAddTraits(.isHeader).padding(.bottom, 12)
            ForEach(BatteryCategory.allCases) { item in
                Button { category = item } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.symbol).frame(width: 22).foregroundStyle(Theme.ok)
                            .accessibilityHidden(true)
                        Text(item.title).font(AppFont.body).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }.padding(12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(selected == item ? Theme.ok.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: Radius.control))
                        .contentShape(RoundedRectangle(cornerRadius: Radius.control))
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selected == item ? .isSelected : [])
            }
        }
    }
    @ViewBuilder private var detail: some View {
        switch selected {
        case .protection:
            if let snapshot = model.snapshot, snapshot.present { protection(snapshot) }
            else { Text("Aucune batterie interne détectée.").foregroundStyle(Theme.muted) }
        case .profiles: BatteryProfilesView(model: model)
        case .discharge: BatteryDischargeView(model: model)
        case .schedules: BatterySchedulesView(model: model)
        case .history: BatteryHistoryView(model: model)
        case .devices: MobileDeviceWiFiView()
        }
    }
    private var footer: some View {
        AdaptiveActionRow {
            VStack(alignment: .leading, spacing: 4) {
                Text(selected == .protection ? model.message : selected.title)
                    .font(AppFont.secondary).fixedSize(horizontal: false, vertical: true)
                if selected == .protection && model.pendingChanges {
                    Text("Réglages modifiés · à appliquer").font(AppFont.caption).foregroundStyle(Theme.warn)
                }
            }
        } actions: {
            if selected == .protection, model.snapshot?.present == true {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { actions }
                    VStack(alignment: .trailing, spacing: 10) { actions }
                }
            } else {
                Button { Task { await model.refresh(force: true) } } label: {
                    Label("Actualiser la batterie", systemImage: "arrow.clockwise")
                }.disabled(model.controlsBusy)
            }
        }
        .buttonStyle(SecondaryActionButtonStyle())
        .padding(18).background(Theme.bg)
        .confirmationDialog("Activer la protection de la batterie ?", isPresented: $confirmingActivation, titleVisibility: .visible) {
            Button("Activer la protection") { Task { await model.perform(.enable) } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(model.nativePolicyControl
                 ? "MacCare demandera à macOS une limite de \(model.configuration.limit) %. Elle s’applique en général en quelques secondes, et la charge peut mettre environ une minute à réagir. Désactivez AlDente et tout autre contrôleur avant de continuer. MacCare conserve la recharge optimisée. À l’arrêt, il restaure les réglages de charge initiaux, dès que la batterie n’est plus au-dessus de la limite d’origine. La calibration de macOS peut temporairement imposer une recharge à 100 %."
                 : model.nativeControl
                 ? "MacCare réglera la limite native de macOS à \(model.configuration.limit) %. Désactivez AlDente et tout autre contrôleur avant de continuer. Les protections de macOS restent actives ; un étalonnage Apple peut exceptionnellement charger à 100 %. À la désactivation, à la veille ou lorsque vous quittez MacCare, le réglage initial sera restauré. Après une interruption, l’assistant reprend cette restauration lorsque le Mac est éveillé."
                 : "MacCare pilotera la charge jusqu’à \(model.configuration.limit) %. Désactivez au préalable AlDente et tout autre contrôleur, et réglez la limite native de macOS sur 100 % avec la recharge optimisée désactivée. Le contrôle matériel est expérimental et n’a pas été validé sur toutes les générations de MacBook. À la mise en veille, la charge est rendue à macOS. Après fermeture ou interruption de MacCare, elle est rétablie sous environ 90 secondes lorsque le Mac est éveillé.")
        }
    }
    private func protection(_ snapshot: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Réglages de charge").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Label(model.message, systemImage: model.active && model.protection?.chargeApplication?.registered == false
                  ? "clock.arrow.circlepath" : model.active ? "checkmark.shield" : "shield")
                .fixedSize(horizontal: false, vertical: true)
            if model.protection?.capabilities?.limitation == .hardwareAccessDenied {
                Label("macOS refuse l’accès aux contrôles matériels de charge sur ce Mac. La limite native reste disponible de 80 à 100 %. Les limites sous 80 % et le mode Voile ne peuvent pas être activés avec cette méthode.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            if !snapshot.appleSilicon {
                Text("Le suivi est disponible. Le contrôle de charge de MacCare nécessite un MacBook Apple Silicon.")
            } else if !model.helperEnabled {
                Text("Le suivi fonctionne sans autorisation supplémentaire. Pour suspendre la charge, activez l’assistant système signé de MacCare, puis autorisez-le dans Réglages Système si macOS le demande.")
                    .foregroundStyle(Theme.muted)
                Button(model.requiresApproval ? "Réessayer l’activation de l’assistant…" : "Activer l’assistant système…") {
                    Task { await model.activateHelper() }
                }.buttonStyle(.borderedProminent).disabled(model.controlsBusy)
                if model.requiresApproval {
                    Text("MacCare retente l’enregistrement, puis ouvre les Réglages Système si votre accord est encore nécessaire.")
                        .font(.callout).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            } else if model.helperUpdateRequired {
                Text("Cette version de MacCare utilise un assistant plus récent. La mise à jour restaure d’abord les anciens réglages de charge et peut demander votre accord dans Réglages Système. La protection repart ensuite si elle était active.")
                    .font(.callout).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Button("Mettre à jour l’assistant…") { Task { await model.updateHelper() } }
                    .buttonStyle(.borderedProminent).disabled(model.controlsBusy)
            } else if model.restoring && !model.restorationDeferred {
                Text("MacCare restaure l’état de charge d’origine. L’assistant continue les tentatives ; aucune nouvelle protection ne peut démarrer pendant cette opération.")
                    .foregroundStyle(Theme.warn)
            } else if model.protection == nil {
                Text("L’état du contrôleur n’a pas pu être vérifié. Actualisez ou vérifiez la version et l’activation de l’assistant système.")
                    .foregroundStyle(Theme.muted)
                Button("Réparer l’assistant système…") { Task { await model.repairHelper() } }
                    .disabled(model.controlsBusy)
                Text("MacCare réenregistre l’assistant uniquement si macOS confirme qu’il ne peut plus démarrer. La protection n’est pas activée par cette réparation.")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            } else if !model.supported && !model.active {
                Text("Les méthodes de contrôle de cette version de MacCare ne sont pas disponibles sur ce Mac. Conservez les protections de macOS et utilisez sa limite de charge si elle est proposée.")
                    .foregroundStyle(Theme.muted)
            }
            if model.supported && !model.recoveryReady {
                Text("L’assistant installé doit être réactivé explicitement pour charger la surveillance de la batterie. Terminez d’abord les tâches d’entretien en cours, puis désactivez et réactivez l’assistant système dans sa rubrique de gestion.")
                    .font(.callout).foregroundStyle(Theme.warn)
            }
            if snapshot.appleSilicon && (model.supported || model.active || !model.helperEnabled) {
                VStack(alignment: .leading, spacing: 16) {
                    if model.nativePolicyControl {
                        Stepper("Limite de charge : \(model.configuration.limit) %", value: $model.configuration.limit, in: 50...100)
                        Text("macOS applique la limite et les pauses demandées, en général en quelques secondes ; la charge peut mettre environ une minute à réagir. Si la batterie est déjà au-dessus de la limite, son niveau est maintenu : ouvrez Décharge contrôlée pour la faire descendre. Si vous abaissez la limite pendant une recharge, la batterie peut encore gagner 3 points avant de s’arrêter. La calibration de macOS peut temporairement imposer 100 %.")
                            .font(.callout).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    } else if model.nativeControl {
                        Picker("Limite de charge", selection: $model.configuration.limit) {
                            ForEach(model.availableLimits, id: \.self) { limit in Text("\(limit) %").tag(limit) }
                        }.pickerStyle(.menu)
                        Text("Limite native de macOS · les valeurs proposées par votre Mac sont disponibles ici. macOS peut exceptionnellement recharger à 100 % pour étalonner la batterie.")
                            .font(.callout).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Stepper("Limite de charge : \(model.configuration.limit) %", value: $model.configuration.limit, in: 50...100, step: 5)
                    }
                    if !model.usesAppleChargeControl {
                    Text(model.protection?.firmwareManaged == true
                         ? "80 % convient à un usage fréquent sur secteur. Le firmware gère une plage de 3 points et peut laisser la batterie redescendre vers cette plage même sur secteur."
                         : "80 % convient à un usage fréquent sur secteur. La charge reprend après une baisse de 3 points. Abaisser la limite ne force pas la décharge.")
                        .font(.callout).foregroundStyle(Theme.muted)
                    }
                    Toggle("Utiliser une plage de maintien (mode Voile)", isOn: Binding(
                        get: { model.configuration.sailingWidth != nil },
                        set: { model.configuration.sailingWidth = $0 ? 5 : nil }
                    )).disabled(!model.supportsSailing || model.controlsBusy)
                    if let width = model.configuration.sailingWidth {
                        Stepper("Reprise à \(model.configuration.limit - width) % · limite \(model.configuration.limit) %", value: Binding(
                            get: { model.configuration.sailingWidth ?? 5 }, set: { model.configuration.sailingWidth = $0 }
                        ), in: 2...20)
                        Text("La charge reste en pause dans cette plage et reprend à sa borne basse. Abaisser la limite ne lance pas une décharge volontaire.")
                            .font(.callout).foregroundStyle(Theme.muted)
                    } else if !model.supportsSailing {
                        Text("La plage personnalisée nécessite un contrôleur matériel compatible. Avec la limite native, macOS choisit la reprise.")
                            .font(.callout).foregroundStyle(Theme.muted)
                    }
                    Toggle("Suspendre la charge si la batterie chauffe", isOn: $model.configuration.thermalProtection)
                        .toggleStyle(.switch).disabled(!model.supportsThermalProtection)
                    if model.nativeControl {
                        Text("La pause thermique personnalisée n’est pas disponible avec la limite native. Les protections thermiques de macOS restent actives.")
                            .font(.callout).foregroundStyle(Theme.muted)
                    } else if model.protection?.firmwareManaged == true {
                        Text("Ce firmware gère directement la limite de charge. Ce contrôle matériel reste expérimental. La pause thermique personnalisée n’est pas disponible ; les protections thermiques de macOS restent actives.")
                            .font(.callout).foregroundStyle(Theme.muted)
                    }
                    if model.configuration.thermalProtection {
                        Stepper("Température maximale : \(model.configuration.maximumTemperature) °C",
                                value: $model.configuration.maximumTemperature, in: 30...45)
                        Text(model.nativePolicyControl
                             ? "La reprise nécessite une baisse de 2 °C et au moins cinq minutes depuis le dernier dépassement. Une température manquante entraîne une demande de pause."
                             : "La charge reprend après une baisse de 2 °C. Une température manquante pendant la protection entraîne une pause de charge.")
                            .font(.callout).foregroundStyle(Theme.muted)
                    }
                }.disabled(model.controlsBusy)
                if model.pendingChanges {
                    Text("Réglages modifiés · appliquez-les pour mettre à jour la protection en cours.")
                        .font(.callout).foregroundStyle(Theme.warn)
                }
            }
            DisclosureGroup("Fonctionnement et compatibilité") {
                VStack(alignment: .leading, spacing: 16) {
                    if model.supported || model.active {
                        VStack(alignment: .leading, spacing: 6) {
                            LoginLaunchToggle()
                            Text("Nécessaire pour que la protection reprenne après un redémarrage. MacCare démarre alors dans la barre des menus.")
                                .font(.callout).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        Text("La protection reste active quand vous fermez la fenêtre et que MacCare reste dans la barre des menus. Quitter l’app ou installer une mise à jour restaure l’état de charge d’origine ; en cas d’interruption, l’assistant reprend cette restauration. La protection repart à la prochaine ouverture de MacCare, sauf si vous l’avez désactivée ou si MacCare l’a arrêtée après une erreur. Après une veille, MacCare doit reprendre contact avant de relancer la protection. " + (model.nativePolicyControl
                             ? "Pendant la veille, macOS conserve votre limite."
                             : "Pendant la veille, macOS peut dépasser votre limite."))
                            .font(.callout).foregroundStyle(Theme.muted)
                        Text(model.usesAppleChargeControl
                             ? "Utilisez un seul contrôleur de charge à la fois. Désactivez AlDente et les autres contrôleurs. MacCare conserve la recharge optimisée et restaure votre limite native initiale à l’arrêt."
                             : "Utilisez un seul contrôleur de charge à la fois. Pour utiliser MacCare, désactivez AlDente et la recharge optimisée, puis réglez la limite native de macOS sur 100 %.")
                            .font(.callout).foregroundStyle(Theme.muted)
                    }
                    Button("Afficher le diagnostic de compatibilité…") {
                        showingDiagnostics = true; diagnostics = "Lecture du diagnostic…"
                        Task { do { diagnostics = try await HelperClient.batteryHardwareDiagnostics() } catch { diagnostics = error.localizedDescription } }
                    }.disabled(!model.helperEnabled || model.controlsBusy)
                    Button("Ouvrir les réglages Batterie de macOS…") { model.openBatterySettings() }
                }.padding(.top, 12)
            }
        }
        .buttonStyle(SecondaryActionButtonStyle())
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg.opacity(0.55), in: RoundedRectangle(cornerRadius: Radius.card))
    }
    @ViewBuilder private var actions: some View {
        if model.active {
            Button("Appliquer les réglages") { Task { await model.perform(.enable) } }
                .disabled(model.busy || !model.pendingChanges || model.cycle != nil || model.protection?.ownedByCaller != true).buttonStyle(.borderedProminent)
            Button(model.protection?.topUp == true ? "Revenir à la limite" : "Recharger à 100 % une fois") {
                Task { await model.perform(model.protection?.topUp == true ? .cancelTopUp : .topUp) }
            }.disabled(model.busy || model.snapshot?.onAC != true || model.protection?.ownedByCaller != true)
            Button("Désactiver la protection") { Task { await model.perform(.disable) } }.disabled(model.controlsBusy)
        } else {
            Button("Activer la protection") { confirmingActivation = true }
                .buttonStyle(.borderedProminent).disabled(model.busy || !model.helperEnabled || !model.supported || !model.recoveryReady || (model.restoring && !model.restorationDeferred))
        }
    }
}
