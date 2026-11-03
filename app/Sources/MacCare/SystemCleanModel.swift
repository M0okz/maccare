import Foundation
import ServiceManagement
import SwiftUI
import MacCareHelperProtocol

/// Nettoyage système (lot 7) : journaux de `/Library/Logs` et `/private/var/log`, supprimés par un
/// assistant privilégié que l'utilisateur active explicitement (voir `docs/architecture.md`).
///
/// L'app ne désigne jamais un chemin : elle lit la liste que l'assistant énumère lui-même et lui
/// renvoie des **identités** `(volume, inode)`. La suppression est **définitive** ; rien n'est coché
/// d'office et l'état d'activation est toujours lu auprès de macOS.
@MainActor
final class SystemCleanModel: ObservableObject {
    struct RuleDef: Identifiable, Hashable {
        let id: String
        let title: String
        let detail: String
    }

    /// Les règles fermées de la v1 (leurs identifiants sont compilés dans le moteur).
    static let rules: [RuleDef] = [
        RuleDef(id: "sys.logs.library", title: "Journaux système",
                detail: "Fichiers de /Library/Logs de plus de 30 jours."),
        RuleDef(id: "sys.logs.diagnostic-reports", title: "Rapports de plantage",
                detail: "Rapports de /Library/Logs/DiagnosticReports de plus de 30 jours."),
        RuleDef(id: "sys.logs.rotated", title: "Journaux archivés",
                detail: "Archives de rotation déjà fermées dans /private/var/log (.gz, .bz2, .xz, .0, .1…)."),
    ]

    struct Item: Decodable, Identifiable, Hashable {
        let rel_path: String
        let size_bytes: UInt64
        let modified: Int64
        let identity: FileIdentity
        var id: String { "\(identity.device)-\(identity.inode)" }
        var modifiedDate: Date { Date(timeIntervalSince1970: TimeInterval(modified)) }
    }

    struct Listing: Decodable {
        let items: [Item]?
        let skipped: [[String]]?
        let truncated: Bool?
        let error: String?
    }

    struct RemoveReport: Decodable {
        let removed: Int?
        let freed_bytes: UInt64?
        let refused: [[String]]?
        let not_found: Int?
        let truncated: Bool?
        let error: String?
    }

    struct JournalEntry: Decodable, Identifiable {
        let date: String
        let rule: String?
        let operation: String?
        let removed: Int?
        let freed_bytes: UInt64?
        let refused: [String]?
        let error: String?
        var id: String { date + (rule ?? "") + (operation ?? "") }
        var parsedDate: Date? { ISO8601DateFormatter().date(from: date) }
    }

    /// État du service, lu auprès de macOS (jamais mémorisé).
    @Published private(set) var status: SMAppService.Status = HelperClient.status
    @Published private(set) var itemsByRule: [String: [Item]] = [:]
    @Published private(set) var truncated = false
    @Published var selection: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRemoving = false
    @Published private(set) var hasLoaded = false
    @Published var statusMessage: String?
    @Published private(set) var lastSummary: String?
    @Published private(set) var lastNeedsAttention = false
    @Published private(set) var journal: [JournalEntry] = []

    /// Ce que l'utilisateur peut faire : macOS rapporte `.notFound` pour un démon **pas encore
    /// enregistré** (constaté dans le journal du gestionnaire de tâches : « record not found »), tout
    /// comme pour un plist absent du paquet ; on distingue donc les deux en regardant le paquet.
    enum Phase { case off, needsApproval, on, unavailable }

    private var plistInBundle: Bool {
        FileManager.default.fileExists(atPath: Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons/\(HelperIdentity.daemonPlist)").path)
    }

    var phase: Phase {
        switch status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        case .notRegistered: return .off
        case .notFound: return plistInBundle ? .off : .unavailable
        @unknown default: return .unavailable
        }
    }

    var isEnabled: Bool { status == .enabled }
    var allItems: [Item] { Self.rules.flatMap { itemsByRule[$0.id] ?? [] } }
    var totalSize: UInt64 { allItems.reduce(0) { $0 + $1.size_bytes } }
    var selectedItems: [Item] { allItems.filter { selection.contains($0.id) } }
    var selectedSize: UInt64 { selectedItems.reduce(0) { $0 + $1.size_bytes } }

    /// Texte honnête de l'état d'activation.
    var statusText: String {
        switch phase {
        case .on: return "Activé"
        case .needsApproval: return "En attente de votre approbation dans les Réglages Système"
        case .off: return "Désactivé"
        case .unavailable: return "Indisponible : l'assistant est absent de ce paquet MacCare"
        }
    }

    func refreshStatus() { status = HelperClient.status }

    // MARK: Activation

    func enable() {
        statusMessage = nil
        var registerError: Error?
        do { try HelperClient.register() } catch { registerError = error }
        refreshStatus()
        // Pour un démon, `register()` signale « Operation not permitted » quand l'approbation de
        // l'utilisateur est requise : c'est le chemin normal, pas un échec à afficher.
        if let registerError, status != .requiresApproval, status != .enabled {
            statusMessage = "Activation impossible : \(registerError.localizedDescription)"
        }
        if status == .enabled { load() }
    }

    func disable() {
        statusMessage = nil
        Task {
            do { try await HelperClient.unregister() } catch { statusMessage = "Désactivation impossible : \(error.localizedDescription)" }
            refreshStatus()
            itemsByRule = [:]; selection = []; hasLoaded = false
        }
    }

    func openApproval() { HelperClient.openApproval() }

    // MARK: Lecture

    func load() {
        refreshStatus()
        guard isEnabled, !isLoading else { return }
        isLoading = true
        statusMessage = nil
        Task {
            var found: [String: [Item]] = [:]
            var anyTruncated = false
            var failure: String?
            for rule in Self.rules {
                do {
                    let json = try await HelperClient.list(rule: rule.id)
                    let listing = try JSONDecoder().decode(Listing.self, from: Data(json.utf8))
                    if let e = listing.error { failure = e; continue }
                    found[rule.id] = (listing.items ?? []).sorted { $0.size_bytes > $1.size_bytes }
                    anyTruncated = anyTruncated || listing.truncated == true
                } catch {
                    failure = error.localizedDescription
                }
            }
            itemsByRule = found
            truncated = anyTruncated
            // Une sélection qui ne correspond plus à rien est abandonnée.
            selection.formIntersection(allItems.map(\.id))
            statusMessage = failure.map { "Lecture incomplète : \($0)" }
            isLoading = false
            hasLoaded = true
            await loadJournal()
        }
    }

    func toggle(_ item: Item) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func selectNone() { selection = [] }

    // MARK: Suppression définitive

    /// Supprime **définitivement** la sélection. À n'appeler qu'après confirmation explicite.
    func removeSelected() {
        let chosen = selectedItems
        guard isEnabled, !chosen.isEmpty, !isRemoving else { return }
        isRemoving = true
        statusMessage = nil
        lastSummary = nil
        // Les identités sont envoyées règle par règle : l'assistant réénumère chaque règle.
        let plan: [(RuleDef, [Item])] = Self.rules.compactMap { rule in
            let items = chosen.filter { item in itemsByRule[rule.id]?.contains(item) == true }
            return items.isEmpty ? nil : (rule, items)
        }
        Task {
            var removed = 0
            var freed: UInt64 = 0
            var refusedReasons: [String] = []
            var failures: [String] = []
            for (rule, items) in plan {
                do {
                    let json = try await HelperClient.remove(rule: rule.id, identities: items.map(\.identity))
                    let report = try JSONDecoder().decode(RemoveReport.self, from: Data(json.utf8))
                    if let e = report.error { failures.append(e); continue }
                    removed += report.removed ?? 0
                    freed += report.freed_bytes ?? 0
                    refusedReasons += (report.refused ?? []).compactMap(\.last)
                } catch {
                    failures.append(error.localizedDescription)
                }
            }
            var parts = ["\(removed) fichier(s) supprimé(s) définitivement, \(humanSize(freed)) libérés"]
            if !refusedReasons.isEmpty { parts.append("\(refusedReasons.count) refusé(s) par sûreté (\(Set(refusedReasons).sorted().joined(separator: ", ")))") }
            if !failures.isEmpty { parts.append("échec : \(Set(failures).sorted().joined(separator: ", "))") }
            lastSummary = parts.joined(separator: " · ")
            lastNeedsAttention = !refusedReasons.isEmpty || !failures.isEmpty
            selection = []
            isRemoving = false
            isLoading = false
            load()
        }
    }

    // MARK: Historique

    func loadJournal() async {
        guard isEnabled else { return }
        let since = Date().addingTimeInterval(-90 * 86_400)
        guard let json = try? await HelperClient.journal(since: since),
              let all = try? JSONDecoder().decode([JournalEntry].self, from: Data(json.utf8)) else { return }
        // Seules les suppressions comptent pour l'utilisateur ; les lectures restent dans le journal de l'assistant.
        journal = all.filter { $0.operation == "remove" }.sorted { ($0.parsedDate ?? .distantPast) > ($1.parsedDate ?? .distantPast) }
    }

    func title(forRule id: String?) -> String {
        Self.rules.first { $0.id == id }?.title ?? (id ?? "")
    }
}
