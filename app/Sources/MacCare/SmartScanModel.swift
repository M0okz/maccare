import Foundation
import SwiftUI

/// Empêche App Nap d'étrangler le process pendant un travail initié par l'utilisateur.
/// C'est la cause observée en Phase A : fenêtre en arrière-plan → scan qui n'avançait plus.
/// Le jeton doit vivre toute la durée du travail ; `endActivity` est appelé au `defer`.
enum PowerAssertion {
    static func beginUserActivity(_ reason: String) -> NSObjectProtocol {
        ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: reason)
    }
    static func end(_ token: NSObjectProtocol) {
        ProcessInfo.processInfo.endActivity(token)
    }

    /// Enveloppe un travail synchrone (un seul appel moteur) hors App Nap.
    static func during<T>(_ reason: String, _ work: () throws -> T) rethrows -> T {
        let token = beginUserActivity(reason)
        defer { end(token) }
        return try work()
    }
}

/// Un groupe de résultats du Smart Scan : une catégorie et ses éléments.
struct ScanGroup: Identifiable {
    let category: CleaningCategory
    let items: [ScanItem]
    let size: UInt64
    let containerOwners: [String: String]
    var id: String { category.id }

    init(category: CleaningCategory, items: [ScanItem], containerOwners: [String: String] = [:]) {
        self.containerOwners = containerOwners
        self.category = category
        self.items = items
        size = items.reduce(0) { $0 + $1.size_bytes }
    }
}

/// Smart Scan : un seul geste lance tous les scans sûrs, agrège les résultats par catégorie,
/// montre une progression et un total, puis déplace vers la corbeille ce que l'utilisateur garde.
@MainActor
final class SmartScanModel: ObservableObject {
    enum Stage: Equatable { case idle, scanning, results, cleaning }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var progress: Double = 0      // 0…1
    @Published var currentLabel: String?
    @Published private(set) var groups: [ScanGroup] = [] {
        didSet { cachedApplications = nil }
    }
    private var cachedApplications: [SmartScanAppResult]?
    var applications: [SmartScanAppResult] {
        if let cachedApplications { return cachedApplications }
        let result = SmartScanAppResult.group(groups)
        cachedApplications = result
        return result
    }
    @Published var selection: Set<String> = []
    @Published var statusMessage: String?
    @Published private(set) var cleanup: SmartScanCleanup?
    var hasPendingCaches: Bool { cleanup?.waiting.isEmpty == false }
    /// Progression en direct du moteur : entrées lues et octets examinés depuis le début du scan.
    @Published private(set) var liveEntries: UInt64 = 0
    @Published private(set) var liveBytes: UInt64 = 0
    /// Vrai seulement si le dernier scan est allé jusqu'au bout : un scan annulé ne permet pas
    /// de juger l'état du Mac (voir le tableau de bord).
    @Published private(set) var isComplete = false
    /// Vrai si le dernier scan a été arrêté par l'utilisateur : on ne le relance pas d'office.
    @Published private(set) var wasCancelled = false
    /// Dernier Smart Scan **complet**, mémorisé : la barre des menus l'affiche même après relance.
    @Published private(set) var lastCompletedAt: Date?
    @Published private(set) var lastSafeBytes: UInt64
    @Published private(set) var lastBreakdown: HomeCleaningBreakdown?
    /// Appelé à la fin de chaque scan complet (espace sûr, espace détecté) : sert au planificateur.
    var onComplete: ((UInt64, UInt64) -> Void)?

    private enum LastScan {
        static let dateKey = "lastSmartScanDate"
        static let safeKey = "lastSmartScanSafeBytes"
        static let breakdownKey = "lastSmartScanSafeBreakdown"
        static func bytes(_ key: String, defaults: UserDefaults) -> UInt64 {
            (defaults.object(forKey: key) as? NSNumber)?.uint64Value ?? 0
        }
    }

    /// Lue à chaque scan : suit le réglage « Outils pour développeurs ».
    private let categorySource: () -> [CleaningCategory]
    private let defaults: UserDefaults
    private var categories: [CleaningCategory] { categorySource() }

    private let makeCacheLookup: @Sendable () -> RunningCacheApplications.Lookup

    init(categories: @escaping () -> [CleaningCategory] = { ScanPreferences.currentCategories },
         defaults: UserDefaults = .standard,
         makeCacheLookup: @escaping @Sendable () -> RunningCacheApplications.Lookup = { RunningCacheApplications.liveLookup() }) {
        self.makeCacheLookup = makeCacheLookup
        categorySource = categories
        self.defaults = defaults
        let completedAt = defaults.object(forKey: LastScan.dateKey) as? Date
        let bytes = LastScan.bytes(LastScan.safeKey, defaults: defaults)
        lastCompletedAt = completedAt
        lastSafeBytes = bytes
        let saved = defaults.dictionary(forKey: LastScan.breakdownKey)
        if let completedAt, saved?["date"] as? Date == completedAt {
            lastBreakdown = HomeCleaningBreakdown(stored: saved?["parts"], total: bytes)
        } else {
            lastBreakdown = nil
        }
    }
    /// Tâche moteur du scan en cours (annulation, progression).
    private var task: EngineTask?
    /// Incrémenté à chaque scan : un résultat d'un scan précédent est ignoré.
    private var generation = 0

    // Progression continue de l'anneau. Le travail d'une catégorie n'est pas connu d'avance ;
    // on s'appuie sur les entrées lues par catégorie lors du dernier scan complet, et à défaut
    // sur une avance asymptotique à l'intérieur de la catégorie en cours.
    private static let expectedKey = "smartScanExpectedEntries"
    private var expectedEntries: [String: UInt64] = [:]
    private var measuredEntries: [String: UInt64] = [:]
    private var categoriesDone = 0
    private var categoryStartEntries: UInt64 = 0

    // Réglages partagés avec le module Nettoyage (mêmes clés UserDefaults).
    private var directDelete: Bool { defaults.bool(forKey: "directDelete") }
    private var logThresholdKB: Int {
        return (defaults.object(forKey: "logThresholdKB") as? NSNumber)?.intValue ?? 10
    }
    private var userExclusions: [String] {
        defaults.stringArray(forKey: "userExclusions") ?? []
    }

    var directDeleteEnabled: Bool { directDelete }
    var allItems: [ScanItem] { groups.flatMap(\.items) }
    var foundSize: UInt64 { groups.reduce(0) { $0 + $1.size } }
    var foundCount: Int { groups.reduce(0) { $0 + $1.items.count } }
    /// Espace récupérable sans risque (règles « sûr » uniquement) : base du tableau de bord.
    var safeSize: UInt64 { groups.filter { $0.category.risk == .safe }.reduce(0) { $0 + $1.size } }
    var safeCount: Int { groups.filter { $0.category.risk == .safe }.reduce(0) { $0 + $1.items.count } }
    var selectedItems: [ScanItem] { allItems.filter { selection.contains($0.id) } }
    var selectedSize: UInt64 { selectedItems.reduce(0) { $0 + $1.size_bytes } }
    var hasRun: Bool { stage != .idle }

    // MARK: Scan

    /// Revient à la préparation sans analyser ni effacer le dernier bilan mémorisé.
    func prepareForNewScan() {
        guard stage != .cleaning else { return }
        task?.cancel()
        task = nil
        generation += 1
        stage = .idle
        progress = 0
        groups = []
        selection = []
        currentLabel = nil
        statusMessage = nil
        cleanup = nil
        liveEntries = 0
        liveBytes = 0
        isComplete = false
        wasCancelled = false
        expectedEntries = [:]
        measuredEntries = [:]
        categoriesDone = 0
        categoryStartEntries = 0
    }

    func scan() {
        guard stage != .cleaning else { return }
        cleanup = nil
        startScan()
    }

    private func startScan() {
        let cats = categories
        guard !cats.isEmpty else {
            task?.cancel()
            generation += 1
            stage = .idle
            groups = []
            selection = []
            currentLabel = nil
            isComplete = false
            statusMessage = "Aucune catégorie incluse. Choisissez un profil dans MacCare → Réglages → Analyse."
            return
        }
        // Un scan précédent encore en vol est arrêté ; ses résultats tardifs seront ignorés.
        task?.cancel()
        let task = EngineTask()
        self.task = task
        generation += 1
        let gen = generation

        stage = .scanning
        progress = 0
        isComplete = false
        wasCancelled = false
        expectedEntries = ((defaults.dictionary(forKey: Self.expectedKey) as? [String: NSNumber]) ?? [:])
            .mapValues(\.uint64Value)
        measuredEntries = [:]
        categoriesDone = 0
        categoryStartEntries = 0
        groups = []
        selection = []
        statusMessage = nil
        liveEntries = 0
        liveBytes = 0

        let threshold = logThresholdKB
        let exclusions = userExclusions

        // Compteurs en direct, lus dans le moteur pendant qu'il travaille.
        Task { @MainActor in
            while self.generation == gen && self.stage == .scanning {
                let p = task.progress
                if self.liveEntries != p.entries { self.liveEntries = p.entries }
                if self.liveBytes != p.bytes { self.liveBytes = p.bytes }
                self.advanceProgress(entries: p.entries, of: cats)
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        Task.detached(priority: .userInitiated) {
            // Jeton tenu pendant tout le scan, à travers les points de suspension.
            let token = PowerAssertion.beginUserActivity("MacCare · Smart Scan")
            defer { PowerAssertion.end(token) }

            var cancelled = false
            for (i, cat) in cats.enumerated() {
                await MainActor.run {
                    guard self.generation == gen else { return }
                    self.currentLabel = "Analyse · \(cat.title)"
                    self.categoryStartEntries = task.progress.entries
                }
                let t: UInt64? = cat.usesThreshold ? UInt64(max(0, threshold)) * 1024 : nil
                let rule = cat.ruleTOML(thresholdBytes: t, userExclusions: exclusions)
                do {
                    let items = try Engine.scan(ruleTOML: rule, task: task)
                    var owners: [String: String] = [:]
                    if cat.category == "container-cache" {
                        for owner in Set(items.compactMap(\.owner)) {
                            owners[owner] = RunningCacheApplications.containerIdentifier(owner, root: cat.root)
                        }
                    }
                    let eligible = items.filter { SmartScanAppProfile.includes($0, containerOwners: owners) }
                    let group = ScanGroup(category: cat, items: eligible.sorted { $0.size_bytes > $1.size_bytes }, containerOwners: owners)
                    await MainActor.run {
                        guard self.generation == gen else { return }
                        self.groups.append(group)
                        // Seules les règles « sûr » sont présélectionnées ; celles à revoir restent décochées.
                        if cat.risk == .safe { self.selection.formUnion(group.items.map(\.id)) }
                        let now = task.progress.entries
                        self.measuredEntries[cat.id] = now - min(now, self.categoryStartEntries)
                        self.categoriesDone = i + 1
                        self.advanceProgress(entries: now, of: cats)
                    }
                } catch Engine.EngineError.cancelled {
                    cancelled = true
                    break
                } catch {
                    await MainActor.run {
                        guard self.generation == gen else { return }
                        self.statusMessage = error.localizedDescription
                        self.currentLabel = nil
                        self.stage = .idle
                    }
                    return
                }
            }
            let wasCancelled = cancelled
            await MainActor.run {
                guard self.generation == gen else { return }
                self.currentLabel = nil
                if wasCancelled {
                    self.wasCancelled = true
                    // Les catégories déjà terminées restent exploitables ; sinon retour à l'accueil.
                    self.statusMessage = self.groups.isEmpty
                        ? "Analyse interrompue."
                        : "Analyse interrompue : résultats partiels (\(self.groups.count) \(pl(self.groups.count, "catégorie")) sur \(cats.count))."
                    self.stage = self.groups.isEmpty ? .idle : .results
                } else {
                    self.progress = 1
                    self.isComplete = true
                    self.defaults.set(self.measuredEntries.mapValues { NSNumber(value: $0) }, forKey: Self.expectedKey)
                    self.stage = .results
                    let now = Date(), safe = self.safeSize
                    self.lastCompletedAt = now
                    self.lastSafeBytes = safe
                    let breakdown = HomeCleaningBreakdown(groups: self.groups)
                    self.lastBreakdown = breakdown
                    self.defaults.set(now, forKey: LastScan.dateKey)
                    self.defaults.set(NSNumber(value: safe), forKey: LastScan.safeKey)
                    self.defaults.set(["date": now, "parts": breakdown.stored], forKey: LastScan.breakdownKey)
                    self.onComplete?(safe, self.foundSize)
                }
            }
        }
    }

    /// Fait avancer l'anneau sans jamais reculer ni atteindre 100 % avant la fin réelle.
    private func advanceProgress(entries: UInt64, of cats: [CleaningCategory]) {
        let n = Double(max(1, cats.count))
        let byCategory = Double(categoriesDone) / n
        var estimate = byCategory
        let expected = cats.compactMap { expectedEntries[$0.id] }
        if expected.count == cats.count, case let total = expected.reduce(0, +), total > 0 {
            // Un scan complet précédent donne le volume de travail attendu.
            estimate = Double(entries) / Double(total)
        } else if categoriesDone < cats.count {
            // Premier scan : avance asymptotique dans la catégorie en cours (jamais au-delà de 90 %).
            let inCategory = Double(entries - min(entries, categoryStartEntries))
            estimate = byCategory + 0.9 * (1 - exp(-inCategory / 30_000)) / n
        }
        let next = min(0.99, max(byCategory, estimate))
        if next > progress { progress = next }
    }

    /// Interrompt le scan en cours. Le moteur rend la main en moins de 50 ms ; les catégories déjà
    /// analysées restent affichées.
    func cancelScan() {
        guard stage == .scanning else { return }
        task?.cancel()
    }

    // MARK: Sélection

    func toggle(_ item: ScanItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func isGroupFullySelected(_ group: ScanGroup) -> Bool {
        !group.items.isEmpty && group.items.allSatisfy { selection.contains($0.id) }
    }

    func toggleGroup(_ group: ScanGroup) {
        let ids = group.items.lazy.map(\.id)
        if isGroupFullySelected(group) { selection.subtract(ids) }
        else { selection.formUnion(ids) }
    }

    func selectAll() { selection = Set(allItems.map(\.id)) }
    func selectNone() { selection = [] }

    // MARK: Nettoyage

    func cleanSelected() {
        clean(selectedItems, direct: directDelete, retry: false)
    }

    func cleanSelected(in applicationID: String) {
        guard let application = applications.first(where: { $0.id == applicationID }) else { return }
        clean(application.items.filter { selection.contains($0.id) }, direct: directDelete, retry: false, refreshAll: false)
    }

    func retryPendingCaches() {
        guard let waiting = cleanup?.waiting, !waiting.isEmpty else { return }
        // Une préférence modifiée entre les essais ne transforme pas un accord Corbeille
        // en accord de suppression définitive.
        clean(waiting.map(\.item), direct: directDelete && waiting.allSatisfy(\.direct), retry: true)
    }

    private func clean(_ items: [ScanItem], direct: Bool, retry: Bool, refreshAll: Bool = true) {
        guard stage == .results, !items.isEmpty else { return }
        stage = .cleaning
        statusMessage = nil
        let chosen = Set(items.map(\.id))
        let retained = (cleanup?.waiting ?? []).filter { !chosen.contains($0.item.id) }
        let lookupFactory = makeCacheLookup
        let threshold = logThresholdKB
        let exclusions = userExclusions
        let protectedPaths = exclusions.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL.path }
        let rules = Dictionary(categories.map { category in
            let bytes: UInt64? = category.usesThreshold ? UInt64(max(0, threshold)) * 1024 : nil
            return (category.id, (category, category.ruleTOML(thresholdBytes: bytes, userExclusions: exclusions)))
        }, uniquingKeysWith: { first, _ in first })

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                let token = PowerAssertion.beginUserActivity("MacCare · nettoyage")
                defer { PowerAssertion.end(token) }
                var result = SmartScanCleanup(report: RemovalReport(direct: direct), waiting: retained)
                let blockers = lookupFactory()
                for (ruleID, candidates) in Dictionary(grouping: items, by: \.reason) {
                    guard let (category, rule) = rules[ruleID] else {
                        result.report.refused += candidates.map { ($0.path, "catégorie retirée du profil") }
                        continue
                    }
                    // Une exclusion placée à l’intérieur d’un dossier sélectionné doit
                    // aussi survivre au retrait récursif de ce dossier.
                    let eligible = candidates.filter { item in
                        let prefix = item.path + "/"
                        if protectedPaths.contains(where: { $0 == item.path || $0.hasPrefix(prefix) || item.path.hasPrefix($0 + "/") }) {
                            result.report.refused.append((item.path, "exclusion personnalisée"))
                            return false
                        }
                        return true
                    }
                    if RunningCacheApplications.isApplicationCache(category.category) {
                        for item in eligible {
                            let names = blockers(item, category.root)
                            if names.isEmpty {
                                result.remove([item], category: category, rule: rule)
                            } else {
                                result.waiting.append(DeferredCache(item: item, apps: names, direct: direct))
                            }
                        }
                    } else {
                        if !eligible.isEmpty { result.remove(eligible, category: category, rule: rule) }
                    }
                }
                return result
            }.value

            cleanup = result
            if refreshAll && !retry && result.waiting.isEmpty {
                startScan()
            } else {
                // Conserve les identités d’origine et les choix manuels. Le nouvel essai
                // ne doit ni examiner à nouveau le disque ni sélectionner de nouveaux fichiers.
                groups = groups.map { group in
                    ScanGroup(category: group.category, items: group.items.filter { !result.removedPaths.contains($0.path) }, containerOwners: group.containerOwners)
                }
                selection.subtract(chosen)
                stage = .results
            }
        }
    }
}
