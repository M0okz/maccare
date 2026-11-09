import Foundation
import Combine

@MainActor
final class ApplicationsAnalysisModel: ObservableObject {
    enum Phase { case introduction, inventory, summary }
    @Published private(set) var phase: Phase = .introduction

    /// Revient à la préparation, sans inventaire ni recherche de mises à jour.
    func prepareForNewAnalysis() {
        guard phase != .inventory else { return }
        phase = .introduction
    }

    func analyze(uninstall: UninstallModel, updates: UpdatesModel, insights: ApplicationsInsightsModel? = nil) {
        guard phase != .inventory else { return }
        phase = .inventory
        Task {
            await uninstall.refreshApps()
            uninstall.scanLeftovers()
            insights?.scan(apps: uninstall.apps)
            updates.checkApplications()
            // Le bilan apparaît dès que l’inventaire est prêt. Les contrôles plus longs y progressent.
            phase = .summary
        }
    }
}

/// Un contrôle indisponible ou en échec ne doit jamais être annoncé « aucune mise à jour ».
struct ApplicationUpdateSummary {
    let sources: [UpdateSource]
    private var appSources: [UpdateSource] { sources.filter { $0.isApplicationSource } }
    var count: Int { appSources.reduce(0) { $0 + $1.items.count } }
    var checking: Bool { appSources.contains { $0.state == .checking } }
    var hasErrors: Bool {
        appSources.contains { if case .error = $0.state { return true }; return false }
    }
    var available: Bool { appSources.contains { $0.state == .ok } }

    var title: String {
        if checking { return "Recherche de mises à jour…" }
        if count > 0 { return "\(hasErrors ? "Au moins " : "")\(count) mise\(count == 1 ? "" : "s") à jour disponible\(count == 1 ? "" : "s")" }
        if hasErrors { return "Vérification incomplète" }
        if available { return "Aucune mise à jour détectée" }
        return "Mises à jour à vérifier"
    }
    var detail: String {
        if checking { return "Le bilan se complète pendant que vous explorez vos applications." }
        if hasErrors { return "Certaines sources n’ont pas répondu. Consultez le détail pour réessayer." }
        if !available { return "Les sources compatibles ne sont pas disponibles sur ce Mac." }
        return "Résultats des sources compatibles. Aucune mise à jour n’est installée automatiquement."
    }
}
