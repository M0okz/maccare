import SwiftUI
import MacCareBattery

struct BatteryView: View {
    @ObservedObject var model: BatteryModel
    @State private var tab = 0
    @State private var showingDiagnostics = false
    @State private var diagnostics = "Lecture du diagnostic…"
    @State private var confirmingActivation = false
    @AccessibilityFocusState private var errorFocused: Bool

    var body: some View {
        ZStack {
            CategoryBackground(section: .battery)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let snapshot = model.snapshot {
                        if snapshot.present {
                            telemetry(snapshot)
                            Picker("Rubrique Batterie", selection: $tab) {
                                Text("Réglages").tag(0); Text("Cycles").tag(1)
                                Text("Programmations").tag(2); Text("Historique").tag(3)
                            }.pickerStyle(.segmented)
                            switch tab {
                            case 1: BatteryCyclesView(model: model)
                            case 2: BatterySchedulesView(model: model)
                            case 3: BatteryHistoryView(model: model)
                            default: protection(snapshot); BatteryProfilesView(model: model)
                            }
                        }
                        else { unavailable }
                    } else {
                        ProgressView("Lecture de la batterie…").frame(maxWidth: .infinity).padding(32)
                    }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                            .accessibilityFocused($errorFocused)
                    }
                    Text("La protection peut ralentir le vieillissement de la batterie. La capacité et l’autonomie dépendent aussi de son âge, de la température et de votre utilisation.")
                        .font(.callout).foregroundStyle(Theme.muted)
                }.padding(32).frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .disabled(model.isTerminating)
        .confirmationDialog("Activer la protection de la batterie ?", isPresented: $confirmingActivation, titleVisibility: .visible) {
            Button("Activer la protection") { Task { await model.perform(.enable) } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(model.nativeControl
                 ? "MacCare réglera la limite native de macOS à \(model.configuration.limit) %. Désactivez AlDente et tout autre contrôleur avant de continuer. Les protections de macOS restent actives ; un étalonnage Apple peut exceptionnellement charger à 100 %. À la désactivation, à la veille ou lorsque vous quittez MacCare, le réglage initial sera restauré. Après une interruption, l’assistant reprend cette restauration lorsque le Mac est éveillé."
                 : "MacCare pilotera la charge jusqu’à \(model.configuration.limit) %. Désactivez au préalable AlDente et tout autre contrôleur, et réglez la limite native de macOS sur 100 % avec la recharge optimisée désactivée. Le contrôle matériel est expérimental et n’a pas été validé sur toutes les générations de MacBook. À la mise en veille, la charge est rendue à macOS. Après fermeture ou interruption de MacCare, elle est rétablie sous environ 90 secondes lorsque le Mac est éveillé.")
        }
        .sheet(isPresented: $showingDiagnostics) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Diagnostic de compatibilité").font(.headline)
                Text("Lecture seule des contrôles de batterie. Aucun réglage de charge n’est modifié.").font(.callout)
                ScrollView { Text(diagnostics).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Button("Fermer") { showingDiagnostics = false }.keyboardShortcut(.cancelAction)
            }.padding(24).frame(width: 700, height: 480)
        }
        .onChange(of: model.error) { errorFocused = $0 != nil }
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Batterie").font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text("Suivez sa santé et choisissez comment elle se recharge.")
                    .font(.title3).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button { Task { await model.refresh(force: true) } } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
                .buttonStyle(.bordered).disabled(model.controlsBusy)
        }
    }
    private func telemetry(_ snapshot: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 20) {
                Image(systemName: snapshot.charging ? "battery.100.bolt" : "battery.75percent")
                    .font(.largeTitle).foregroundStyle(Theme.ok).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.percent.map { "\($0) %" } ?? "Niveau indisponible")
                        .font(.largeTitle.weight(.semibold)).monospacedDigit()
                    Text(snapshot.onAC ? (snapshot.charging ? "Branché · en charge" : "Branché · charge en pause") : "Sur batterie")
                        .font(.body).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            if let percent = snapshot.percent {
                ProgressView("Niveau de charge", value: Double(percent), total: 100)
                    .tint(Theme.ok).accessibilityValue("\(percent) pour cent")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)], alignment: .leading, spacing: 18) {
                metric("Capacité restante estimée", value: snapshot.healthPercent.map { "\($0) %" } ?? "Indisponible")
                metric("Cycles de charge", value: snapshot.cycles.map(String.init) ?? "Indisponibles")
                metric("Température de la batterie", value: snapshot.temperature.map { "\($0.formatted(.number.precision(.fractionLength(1)))) °C" } ?? "Indisponible")
            }
        }.padding(24).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.card))
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout).foregroundStyle(Theme.muted)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }.accessibilityElement(children: .combine)
    }
    private func protection(_ snapshot: BatterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Protection de la batterie").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Label(model.message, systemImage: model.active ? "checkmark.shield" : "shield")
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
                Button(model.requiresApproval ? "Autoriser dans Réglages Système…" : "Activer l’assistant système…") {
                    Task { await model.activateHelper() }
                }.buttonStyle(.borderedProminent).disabled(model.controlsBusy)
            } else if model.restoring {
                Text("MacCare restaure l’état de charge d’origine. L’assistant continue les tentatives ; aucune nouvelle protection ne peut démarrer pendant cette opération.")
                    .foregroundStyle(Theme.warn)
            } else if model.protection == nil {
                Text("L’état du contrôleur n’a pas pu être vérifié. Actualisez ou vérifiez la version et l’activation de l’assistant système.")
                    .foregroundStyle(Theme.muted)
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
                    if model.nativeControl {
                        Picker("Limite de charge", selection: $model.configuration.limit) {
                            ForEach(model.availableLimits, id: \.self) { limit in Text("\(limit) %").tag(limit) }
                        }.pickerStyle(.menu)
                        Text("Limite native de macOS · les valeurs proposées par votre Mac sont disponibles ici. macOS peut exceptionnellement recharger à 100 % pour étalonner la batterie.")
                            .font(.callout).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Stepper("Limite de charge : \(model.configuration.limit) %", value: $model.configuration.limit, in: 50...100, step: 5)
                    }
                    if !model.nativeControl {
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
                        Text("La charge reprend après une baisse de 2 °C. Une température manquante pendant la protection entraîne une pause de charge.")
                            .font(.callout).foregroundStyle(Theme.muted)
                    }
                }.disabled(model.controlsBusy)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { actions }
                    VStack(alignment: .leading, spacing: 12) { actions }
                }
                if model.pendingChanges {
                    Text("Réglages modifiés · appliquez-les pour mettre à jour la protection en cours.")
                        .font(.callout).foregroundStyle(Theme.warn)
                }
            }
            Divider()
            if model.supported || model.active {
            Text("La protection reste active quand vous fermez la fenêtre et que MacCare reste dans la barre des menus. Quitter l’app restaure l’état de charge d’origine ; en cas d’interruption, l’assistant reprend cette restauration. Après une veille, MacCare doit reprendre contact avant de relancer la protection. Pendant la veille, macOS peut dépasser votre limite.")
                .font(.callout).foregroundStyle(Theme.muted)
            Text(model.nativeControl
                 ? "Utilisez un seul contrôleur de charge à la fois. Désactivez AlDente et les autres contrôleurs. MacCare conserve la recharge optimisée et restaure votre limite native initiale à l’arrêt."
                 : "Utilisez un seul contrôleur de charge à la fois. Pour utiliser MacCare, désactivez AlDente et la recharge optimisée, puis réglez la limite native de macOS sur 100 %.")
                .font(.callout).foregroundStyle(Theme.muted)
            }
            Button("Afficher le diagnostic de compatibilité…") {
                showingDiagnostics = true; diagnostics = "Lecture du diagnostic…"
                Task { do { diagnostics = try await HelperClient.batteryHardwareDiagnostics() } catch { diagnostics = error.localizedDescription } }
            }.disabled(!model.helperEnabled || model.controlsBusy)
            Button("Ouvrir les réglages Batterie de macOS…") { model.openBatterySettings() }
                .buttonStyle(.borderedProminent)
        }.padding(24).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.card))
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
                .buttonStyle(.borderedProminent).disabled(model.busy || !model.helperEnabled || !model.supported || !model.recoveryReady || model.restoring)
        }
    }
    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Aucune batterie interne détectée", systemImage: "desktopcomputer")
                .font(.title2.weight(.semibold))
            Text("Les Mac mini, iMac, Mac Studio et Mac Pro n’ont pas de batterie interne à protéger. Aucun contrôle de charge n’est proposé sur ces appareils.")
                .foregroundStyle(Theme.muted)
        }.padding(24)
    }
}
