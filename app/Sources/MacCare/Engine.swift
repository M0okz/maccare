import CMacCareCore
import Foundation

/// Jeton d'une tâche longue du moteur (scan, mesure). Pendant que l'appel bloquant tourne sur un
/// thread de travail, on peut en lire la progression et l'annuler depuis n'importe quel thread :
/// le moteur rend alors la main en moins de 50 ms.
final class EngineTask: @unchecked Sendable {
    fileprivate let raw: OpaquePointer?

    init() { raw = maccare_task_new() }
    deinit { maccare_task_free(raw) }

    func cancel() { maccare_task_cancel(raw) }

    /// Entrées de dossier lues et octets comptés depuis le début de la tâche.
    var progress: (entries: UInt64, bytes: UInt64) {
        var entries: UInt64 = 0, bytes: UInt64 = 0
        maccare_task_progress(raw, &entries, &bytes)
        return (entries, bytes)
    }
}

/// Pont typé vers le moteur Rust. Centralise les appels FFI et la gestion mémoire.
enum Engine {
    enum EngineError: Error, LocalizedError {
        case nullReturn
        case decode(String)
        case engine(String)
        /// La tâche a été annulée (voir `EngineTask.cancel`).
        case cancelled

        var errorDescription: String? {
            switch self {
            case .nullReturn: return "le moteur n'a rien renvoyé"
            case .decode(let m): return "réponse illisible : \(m)"
            case .engine(let m): return "erreur moteur : \(m)"
            case .cancelled: return "analyse interrompue"
            }
        }
    }

    static var version: String { String(cString: maccare_version()) }

    /// Scanne selon une règle TOML et renvoie les éléments proposés. Avec une tâche, le scan est
    /// annulable (`EngineError.cancelled`) et sa progression lisible pendant l'appel.
    static func scan(ruleTOML: String, task: EngineTask? = nil) throws -> [ScanItem] {
        let response: ScanResponse = try callJSON({ maccare_scan_rule_task($0, task?.raw) }, ruleTOML)
        if let err = response.error { throw EngineError.engine(err) }
        if response.cancelled == true { throw EngineError.cancelled }
        return response.items ?? []
    }

    /// Valide une sélection contre les gardes de sûreté. Ne supprime rien.
    static func planRemoval(_ input: PlanInput) throws -> [RemovalDecision] {
        let json = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        let response: PlanResponse = try callJSON(maccare_plan_removal, json)
        if let err = response.error { throw EngineError.engine(err) }
        return response.decisions ?? []
    }

    /// Supprime directement (sans corbeille) la sélection, re-validée côté moteur. Irréversible.
    static func executeRemoval(_ input: PlanInput) throws -> [RemovalResult] {
        let json = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        let response: ExecuteResponse = try callJSON(maccare_execute_removal, json)
        if let err = response.error { throw EngineError.engine(err) }
        return response.results ?? []
    }

    /// Métadonnées d'une règle, telles que les lit le moteur (titre, risque, racine développée…).
    struct RuleInfo: Decodable {
        let id: String?
        let title: String?
        let description: String?
        let category: String?
        let risk: String?
        let icon: String?
        let root: String?
        let min_size_setting: Bool?
        let audience: String?
        let error: String?
    }

    /// Lit les métadonnées d'une règle ; nil si le moteur la rejette (règle invalide).
    static func ruleInfo(_ toml: String) -> RuleInfo? {
        guard let info: RuleInfo = try? callJSON(maccare_rule_info, toml), info.error == nil else { return nil }
        return info
    }

    /// Mesure les enfants directs d'un dossier (Espace disque). Ne supprime rien.
    static func measureDir(_ path: String, budgetSecs: UInt64 = 60, task: EngineTask? = nil) throws -> [SpaceChild] {
        let input = MeasureInput(path: path, budget_secs: budgetSecs)
        let json = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        let response: MeasureResponse = try callJSON({ maccare_measure_dir_task($0, task?.raw) }, json)
        if let err = response.error { throw EngineError.engine(err) }
        if response.cancelled == true { throw EngineError.cancelled }
        return response.children ?? []
    }

    /// Recherche les gros fichiers du dossier personnel (hors ~/Library, cachés, paquets).
    /// Annulable via la tâche. Ne supprime rien.
    static func findLargeFiles(minBytes: UInt64, limit: Int = 500, root: String? = nil, task: EngineTask? = nil) throws -> LargeFilesResponse {
        let json = String(decoding: try JSONEncoder().encode(LargeFilesInput(root: root, min_bytes: minBytes, limit: limit)), as: UTF8.self)
        let response: LargeFilesResponse = try callJSON({ maccare_find_large_files_task($0, task?.raw) }, json)
        if let err = response.error { throw EngineError.engine(err) }
        if response.cancelled == true { throw EngineError.cancelled }
        return response
    }

    /// Valide des fichiers personnels choisis par l'utilisateur. Seule la mise à la corbeille est
    /// prévue pour eux : le moteur n'expose aucune suppression directe de ces fichiers.
    static func planUserFiles(root: String, files: [LargeFile]) throws -> [RemovalDecision] {
        let input = UserFilesPlanInput(root: root, items: files.map { PlanItem(path: $0.path, identity: $0.identity) })
        let json = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        let response: PlanResponse = try callJSON(maccare_plan_user_files, json)
        if let err = response.error { throw EngineError.engine(err) }
        return response.decisions ?? []
    }

    /// Recherche les doublons du dossier personnel (hors ~/Library, cachés, paquets, projets de code).
    /// Annulable via la tâche. Ne supprime rien.
    static func findDuplicates(minBytes: UInt64 = 1_048_576, root: String? = nil, task: EngineTask? = nil) throws -> DuplicatesResponse {
        let json = String(decoding: try JSONEncoder().encode(DuplicatesInput(root: root, min_bytes: minBytes)), as: UTF8.self)
        let response: DuplicatesResponse = try callJSON({ maccare_find_duplicates_task($0, task?.raw) }, json)
        if let err = response.error { throw EngineError.engine(err) }
        if response.cancelled == true { throw EngineError.cancelled }
        return response
    }

    /// Valide le retrait de doublons : le moteur exige un exemplaire conservé présent et inchangé,
    /// et compare octet par octet chaque fichier retiré avec lui. Corbeille uniquement.
    static func planDuplicates(_ input: DuplicatesPlanInput) throws -> [RemovalDecision] {
        let json = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        let response: PlanResponse = try callJSON(maccare_plan_duplicates, json)
        if let err = response.error { throw EngineError.engine(err) }
        return response.decisions ?? []
    }

    /// Repère et mesure les corbeilles de l'utilisateur. Ne supprime rien.
    static func listTrashes(task: EngineTask? = nil) throws -> [TrashBin] {
        let response: TrashListResponse = try callJSON({ maccare_list_trashes_task($0, task?.raw) }, "{}")
        if let err = response.error { throw EngineError.engine(err) }
        if response.cancelled == true { throw EngineError.cancelled }
        return response.bins ?? []
    }

    /// Vide **définitivement** les corbeilles données (le moteur n'accepte que celles qu'il repère
    /// lui-même). L'annulation s'arrête entre deux éléments ; le compte rendu reste exact.
    static func emptyTrashes(_ bins: [TrashBin], task: EngineTask? = nil) throws -> TrashEmptyResponse {
        let input = TrashEmptyInput(bins: bins.map { TrashEmptyItem(path: $0.path, identity: $0.identity, snapshot: $0.snapshot) })
        let json = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        let response: TrashEmptyResponse = try callJSON({ maccare_empty_trashes_task($0, task?.raw) }, json)
        if let err = response.error { throw EngineError.engine(err) }
        return response
    }

    /// Liste simulateurs et runtimes Xcode via simctl. Ne supprime rien.
    static func listSimulators(task: EngineTask? = nil) throws -> SimulatorsResponse {
        let response: SimulatorsResponse = try callJSON({ maccare_list_simulators_task($0, task?.raw) }, "{}")
        if let err = response.error { throw EngineError.engine(err) }
        if response.cancelled == true { throw EngineError.cancelled }
        return response
    }

    /// Supprime **définitivement** des simulateurs et runtimes via simctl (liste fermée relue par
    /// le moteur ; simulateur allumé ou runtime non supprimable refusé).
    static func deleteSimulators(_ udids: [String], runtimes: [String], task: EngineTask? = nil) throws -> [SimDeleteResult] {
        let json = String(decoding: try JSONEncoder().encode(SimDeleteInput(simulators: udids, runtimes: runtimes)), as: UTF8.self)
        let response: SimDeleteResponse = try callJSON({ maccare_delete_simulators_task($0, task?.raw) }, json)
        if let err = response.error { throw EngineError.engine(err) }
        return response.results ?? []
    }

    /// Agents de lancement (utilisateur, mis de côté par MacCare, système). Ne modifie rien.
    static func listAgents(task: EngineTask? = nil) throws -> [LaunchAgentInfo] {
        let response: AgentsResponse = try callJSON({ maccare_list_agents_task($0, task?.raw) }, "{}")
        if let err = response.error { throw EngineError.engine(err) }
        return response.agents ?? []
    }

    /// Désactive (`disable`) ou réactive (`enable`) un agent de l'utilisateur. Réversible ; le
    /// moteur relit l'agent dans sa liste fermée et refuse tout agent système ou Apple.
    static func setAgent(_ action: String, _ agent: LaunchAgentInfo) throws -> String {
        guard let identity = agent.identity else { throw EngineError.engine("identité inconnue") }
        let json = String(decoding: try JSONEncoder().encode(AgentActionInput(action: action, path: agent.path, identity: identity)), as: UTF8.self)
        let response: AgentActionResponse = try callJSON({ maccare_set_agent_task($0, nil) }, json)
        if let err = response.error, response.ok != true { throw EngineError.engine(err) }
        return response.path ?? agent.path
    }

    /// Inspecte une liste explicite de chemins (désinstalleur). Ne supprime rien.
    static func inspectPaths(_ paths: [String], category: String = "uninstall") throws -> [ScanItem] {
        let input = InspectInput(category: category, paths: paths)
        let json = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        let response: ScanResponse = try callJSON(maccare_inspect_paths, json)
        if let err = response.error { throw EngineError.engine(err) }
        return response.items ?? []
    }

    // MARK: - Interne

    private typealias CStringFn = (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?

    private static func callJSON<T: Decodable>(_ fn: CStringFn, _ arg: String) throws -> T {
        let raw: UnsafeMutablePointer<CChar>? = arg.withCString { fn($0) }
        guard let raw else { throw EngineError.nullReturn }
        defer { maccare_string_free(raw) }
        let data = Data(String(cString: raw).utf8)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw EngineError.decode("\(error)")
        }
    }
}
