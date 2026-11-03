import SwiftUI
import AppKit
import MacCareMaintenance

struct PerformanceMaintenanceView: View {
    @ObservedObject var app: AppState
    @ObservedObject private var model: PerformanceTasksModel
    @ObservedObject private var helper: SystemCleanModel
    @ObservedObject private var permissions: PermissionsModel
    @ObservedObject private var repairs: MaintenanceModel
    @AppStorage(PerformancePreferences.localSnapshotsKey) private var includeLocalSnapshots = PerformancePreferences.includeLocalSnapshotsDefault
    @State private var focusedTask: PerformanceTask? = .purgeable
    @State private var focusedRepair: MaintenanceTask?
    @State private var confirmation: PerformanceConfirmation?
    @State private var repairConfirmation: MaintenanceTask?
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .title) private var detailTitleSize: CGFloat = 24

    init(app: AppState) {
        self.app = app; model = app.performanceTasks; helper = app.systemClean; permissions = app.permissions; repairs = app.maintenance
    }
    private var busy: Bool { model.isBusy || repairs.running != nil }
    private func unavailable(_ task: PerformanceTask) -> String? {
        PerformanceTaskPresentation.unavailable(task, helperEnabled: helper.isEnabled, fullDiskGranted: permissions.fullDisk == .granted,
            mailRunning: !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty,
            preparing: model.preparing, cacheCount: model.cachePlan?.items.count, cacheError: model.cacheError, includeLocalSnapshots: includeLocalSnapshots)
    }
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
        .task {
            helper.refreshStatus()
            if model.cachePlan == nil && !model.isBusy { model.refresh(exclusions: app.review.userExclusions) }
        }
        .onChange(of: scenePhase) { phase in if phase == .active { helper.refreshStatus() } }
        .sheet(item: $confirmation) { confirmationSheet($0) }
        .sheet(item: $repairConfirmation) { repairSheet($0) }
    }
    private var browser: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Entretien du Mac").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
            Text("Examinez une tâche pour comprendre ses effets, puis cochez celles à exécuter.")
                .font(AppFont.secondary).foregroundStyle(Theme.muted)
            HStack {
                Text("\(PerformanceTask.allCases.count) tâches · \(repairs.tasks.count) réparations").font(AppFont.secondary)
                Spacer(minLength: 0)
                Button { model.refresh(exclusions: app.review.userExclusions) } label: { Image(systemName: "arrow.clockwise").frame(width: 30, height: 32) }
                    .buttonStyle(.plain).disabled(busy).accessibilityLabel("Actualiser le bilan des caches")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Tâches d’entretien").font(AppFont.secondary.weight(.semibold)).foregroundStyle(Theme.muted).padding(.vertical, 8)
                    ForEach(PerformanceTask.allCases) { task in
                        HStack(spacing: 9) {
                            Toggle("Choisir", isOn: Binding(get: { model.selection.contains(task) }, set: { on in
                                if on { model.selection.insert(task) } else { model.selection.remove(task) }
                            })).toggleStyle(.checkbox).labelsHidden().disabled(busy || unavailable(task) != nil)
                                .accessibilityLabel("Sélectionner \(PerformanceTaskPresentation.title(task))")
                            Button { focusedTask = task; focusedRepair = nil } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: task.symbol).foregroundStyle(ModuleColor.startup).frame(width: 22).accessibilityHidden(true)
                                    Text(PerformanceTaskPresentation.title(task)).font(AppFont.body.weight(.medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    if model.running == task { ProgressView().controlSize(.small) }
                                    else if unavailable(task) != nil { Image(systemName: "lock").foregroundStyle(Theme.muted).accessibilityHidden(true) }
                                }.frame(maxWidth: .infinity, minHeight: 32).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Examiner \(PerformanceTaskPresentation.title(task))")
                                .accessibilityAddTraits(focusedTask == task ? .isSelected : [])
                        }.padding(10).background(focusedTask == task ? Theme.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }
                    Text("Réparations ciblées").font(AppFont.secondary.weight(.semibold)).foregroundStyle(Theme.muted).padding(.top, 18).padding(.bottom, 8)
                    ForEach(repairs.tasks) { repair in
                        Button { focusedRepair = repair; focusedTask = nil } label: {
                            Label(repair.title, systemImage: "wrench.and.screwdriver")
                                .font(AppFont.body).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                .background(focusedRepair?.key == repair.key ? Theme.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).accessibilityAddTraits(focusedRepair?.key == repair.key ? .isSelected : [])
                    }
                }
            }
        }.padding(20)
    }
    private var inspection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let task = focusedTask {
                    Text(PerformanceTaskPresentation.title(task)).font(.system(size: detailTitleSize, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Text(task.detail).font(AppFont.body).foregroundStyle(Theme.muted)
                    if let issue = unavailable(task) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(issue, systemImage: "info.circle").font(AppFont.body)
                            if task.requiresHelper(includeLocalSnapshots: includeLocalSnapshots) && !helper.isEnabled { helperActions }
                            if task == .mail && permissions.fullDisk != .granted {
                                Button("Ouvrir les réglages d’accès au disque") { permissions.openFullDiskSettings() }.buttonStyle(SecondaryActionButtonStyle())
                            }
                        }.padding(16).background(Theme.bg, in: RoundedRectangle(cornerRadius: 12))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Effets et précautions").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                        Text(PerformanceTaskPresentation.effect(task, includeLocalSnapshots: includeLocalSnapshots)).font(AppFont.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    if task == .purgeable {
                        Label(includeLocalSnapshots ? "Instantanés locaux inclus · modifiable dans Réglages → Performances"
                              : "Instantanés locaux exclus dans Réglages → Performances", systemImage: "gearshape")
                            .font(AppFont.secondary).foregroundStyle(Theme.muted)
                        if includeLocalSnapshots, let estimate = model.purgeableEstimateBytes {
                            Text("Espace récupérable estimé par macOS : \(humanSize(estimate)). Ce total peut inclure des données que cette action ne libère pas ; le gain n’est pas garanti.")
                                .font(AppFont.secondary).foregroundStyle(Theme.muted)
                        }
                        if includeLocalSnapshots, let error = model.cacheError {
                            Label("Caches indisponibles : \(error). La réduction des instantanés reste disponible.", systemImage: "info.circle")
                                .font(AppFont.secondary).foregroundStyle(Theme.muted)
                        }
                        if model.preparing { ProgressView("Examen des caches…").font(AppFont.body) }
                        else if let plan = model.cachePlan, !plan.items.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("\(humanSize(plan.bytes)) de caches examinés").font(AppFont.section).monospacedDigit().accessibilityAddTraits(.isHeader)
                                DisclosureGroup("\(plan.items.count) application(s) concernée(s)") {
                                    ForEach(plan.items) { item in
                                        HStack {
                                            Text(URL(fileURLWithPath: item.path).lastPathComponent).lineLimit(1).truncationMode(.middle)
                                            Spacer()
                                            Text(humanSize(item.size_bytes)).monospacedDigit()
                                        }.font(AppFont.secondary).padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }
                    if let report = model.reports[task] {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(report.message, systemImage: report.succeeded ? "checkmark.circle" : "exclamationmark.triangle")
                                .font(AppFont.body).foregroundStyle(report.succeeded ? Theme.ok : Theme.warn)
                            if !report.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                DisclosureGroup("Détails du résultat") { Text(report.details).font(.caption.monospaced()).textSelection(.enabled).padding(.top, 8) }
                            }
                        }
                    }
                } else if let repair = focusedRepair {
                    Text(repair.title).font(.system(size: detailTitleSize, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Text(repair.note).font(AppFont.body).foregroundStyle(Theme.muted)
                    Text("Effets et précautions").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
                    Text(repair.effect).font(AppFont.body).foregroundStyle(Theme.muted)
                    if repairs.running == repair.key { ProgressView("Réparation en cours…").font(AppFont.body) }
                    if let result = repairs.results[repair.key] {
                        Label(result.message, systemImage: result.ok ? "checkmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(result.ok ? Theme.ok : Theme.warn)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
        }
    }
    private var helperActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assistant système · \(helper.statusText)").font(AppFont.secondary).foregroundStyle(Theme.muted)
            HStack {
                if helper.phase == .needsApproval { Button("Approuver dans macOS") { helper.openApproval() } }
                else { Button("Activer l’assistant…") { helper.enable() }.disabled(helper.phase == .unavailable) }
                Button("Revérifier") { helper.refreshStatus() }
            }.buttonStyle(SecondaryActionButtonStyle())
            if let message = helper.statusMessage { Text(message).font(AppFont.secondary).foregroundStyle(Theme.muted) }
        }
    }
    private var footer: some View {
        AdaptiveActionRow {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.running.map { "En cours : \(PerformanceTaskPresentation.title($0))" } ?? (repairs.running != nil ? "Réparation en cours…" : (focusedRepair == nil ? "\(model.chosen.count) tâche(s) sélectionnée(s)" : "Réparation individuelle")))
                    .font(AppFont.body.weight(.semibold))
                Text(focusedRepair == nil ? (model.lastSummary ?? "Les effets seront récapitulés avant toute exécution.") : "Cette action lance uniquement la réparation affichée.")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
            }
        } actions: {
            if let repair = focusedRepair {
                Button("Réparer…") { repairConfirmation = repair }.buttonStyle(.borderedProminent).controlSize(.large).disabled(busy)
            } else {
                Button("Exécuter la sélection…") { confirmation = PerformanceConfirmation(tasks: model.chosen, includeLocalSnapshots: includeLocalSnapshots) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(busy || model.chosen.isEmpty || model.chosen.contains { unavailable($0) != nil })
            }
        }.padding(18).background(Theme.sidebar)
    }
    private func confirmationSheet(_ request: PerformanceConfirmation) -> some View {
        let tasks = request.tasks
        let snapshots = request.includeLocalSnapshots && includeLocalSnapshots
        let removesSnapshots = snapshots && tasks.contains(.purgeable)
        return VStack(alignment: .leading, spacing: 18) {
            Text("Exécuter \(tasks.count) tâche(s) ?").font(AppFont.section.weight(.semibold)).accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(tasks) { task in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(PerformanceTaskPresentation.title(task)).font(AppFont.emphasis)
                            Text(PerformanceTaskPresentation.effect(task, includeLocalSnapshots: snapshots)).font(AppFont.body).fixedSize(horizontal: false, vertical: true)
                            if task == .purgeable, let plan = model.cachePlan {
                                Text("Suppression définitive de \(plan.items.count) dossier(s), soit \(humanSize(plan.bytes)) de caches recensés.")
                                    .font(AppFont.body.weight(.semibold))
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Annuler") { confirmation = nil }.keyboardShortcut(.cancelAction)
                Button(removesSnapshots ? "Supprimer des instantanés et exécuter" : "Confirmer l’exécution") {
                    confirmation = nil
                    model.run(tasks, includeLocalSnapshots: snapshots)
                }.buttonStyle(.borderedProminent)
                    .tint(removesSnapshots ? Theme.danger : Theme.accent)
                    .disabled(busy || tasks.contains { unavailable($0) != nil })
            }
        }.padding(28).frame(width: 580, height: 500)
            .foregroundStyle(Color.primary).background(Color.white).preferredColorScheme(.light)
            .interactiveDismissDisabled(model.isBusy)
    }
    private func repairSheet(_ repair: MaintenanceTask) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(repair.title).font(AppFont.section).accessibilityAddTraits(.isHeader)
            Text(repair.effect).font(AppFont.body).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Annuler") { repairConfirmation = nil }.keyboardShortcut(.cancelAction)
                Button("Lancer la réparation") { repairConfirmation = nil; repairs.run(repair) }
                    .buttonStyle(.borderedProminent).disabled(busy)
            }
        }.padding(28).frame(width: 520)
            .foregroundStyle(Color.primary).background(Color.white).preferredColorScheme(.light)
    }
}
