import SwiftUI
import MacCareBattery

struct BatterySchedulesView: View {
    @ObservedObject var model: BatteryModel
    @State private var name = ""
    @State private var firstRun = Date().addingTimeInterval(3600)
    @State private var recurrence = BatterySchedule.Recurrence.daily
    @State private var action = 0
    @State private var limit = 80
    @State private var confirmingCalibration = false
    private var requestedAction: BatteryAutomationAction {
        switch action {
        case 1: return .topUp
        case 2: return .discharge
        case 3: return .calibrate
        case 4: return .disable
        default:
            var value = model.configuration; value.limit = limit
            return .configure(value)
        }
    }
    private func save() {
        let schedule = BatterySchedule(name: name.trimmingCharacters(in: .whitespacesAndNewlines), action: requestedAction,
                                       recurrence: recurrence, firstRun: firstRun)
        Task { await model.saveSchedule(schedule); if model.error == nil { name = "" } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            GroupBox("Programmations") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Les tâches s’exécutent lorsque MacCare est ouvert. Après une interruption de plus de dix minutes, l’occurrence est signalée comme manquée et la suivante est conservée.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if model.schedules.isEmpty { Text("Aucune programmation. Ajoutez un horaire ci-dessous.").foregroundStyle(.secondary) }
                    ForEach(model.schedules) { schedule in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(schedule.name).font(.headline)
                            Text(schedule.action.title)
                            Text("\(schedule.recurrence.title) · \(schedule.enabled ? schedule.nextRun.formatted(date: .abbreviated, time: .shortened) : (schedule.recurrence == .once && schedule.lastClaimed != nil ? "Terminée" : "En pause")) · \(schedule.timeZoneID)")
                                .font(.callout).foregroundStyle(.secondary)
                            HStack {
                                Button(schedule.enabled ? "Mettre en pause" : "Réactiver") { Task { await model.toggleSchedule(schedule) } }
                                Button("Supprimer") { Task { await model.deleteSchedule(schedule.id) } }
                            }.disabled(model.controlsBusy)
                        }
                        Divider()
                    }
                }.padding(12)
            }
            GroupBox("Ajouter une programmation") {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Nom de la programmation", text: $name).textFieldStyle(.roundedBorder)
                    Picker("Action", selection: $action) {
                        Text("Appliquer une limite de charge").tag(0)
                        Text("Recharger à 100 % une fois").tag(1)
                        Text("Décharger jusqu’à la limite").tag(2)
                        Text("Démarrer l’étalonnage").tag(3)
                        Text("Désactiver la protection").tag(4)
                    }
                    if action == 0 {
                        Picker("Limite à appliquer", selection: $limit) {
                            ForEach(model.availableLimits, id: \.self) { Text("\($0) %").tag($0) }
                        }
                        Text("Les autres réglages de protection actuels sont enregistrés avec cette limite.").font(.callout).foregroundStyle(.secondary)
                    }
                    DatePicker("Première exécution", selection: $firstRun, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    Picker("Répétition", selection: $recurrence) {
                        ForEach(BatterySchedule.Recurrence.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if action == 3 {
                        Text("Chaque exécution lance un cycle long : 100 % → 10 % → 100 % → limite. Laissez le Mac et le chargeur disponibles.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Button("Enregistrer la programmation") { if action == 3 { confirmingCalibration = true } else { save() } }
                        .disabled(model.controlsBusy || !model.automationsLoaded || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || firstRun <= .now || ((action == 2 || action == 3) && !model.supportsDischarge))
                }.padding(12)
            }
            GroupBox("Raccourcis et dernières exécutions") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Dans Raccourcis, recherchez MacCare pour régler la limite, recharger à 100 %, désactiver la protection ou démarrer un cycle de batterie.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Ouvrir Raccourcis") { if let url = URL(string: "shortcuts://") { NSWorkspace.shared.open(url) } }
                    if model.automationEvents.isEmpty { Text("Aucune exécution planifiée enregistrée.").foregroundStyle(.secondary) }
                    ForEach(Array(model.automationEvents.prefix(10).enumerated()), id: \.offset) { _, event in Text(event).font(.callout).textSelection(.enabled) }
                }.padding(12)
            }
        }
        .onAppear { if !model.availableLimits.contains(limit), let first = model.availableLimits.first { limit = first } }
        .confirmationDialog("Programmer cet étalonnage complet ?", isPresented: $confirmingCalibration, titleVisibility: .visible) {
            Button("Enregistrer le cycle planifié") { save() }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Cette programmation pourra lancer automatiquement une décharge vers 10 % aux horaires choisis, lorsque MacCare est ouvert et le chargeur branché.") }
    }
}
