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
    var items: [ScanItem]
    var id: String { category.id }
    var size: UInt64 { items.reduce(0) { $0 + $1.size_bytes } }
}

/// Smart Scan : un seul geste lance tous les scans sûrs, agrège les résultats par catégorie,
/// montre une progression et un total, puis déplace vers la corbeille ce que l'utilisateur garde.
@MainActor
final class SmartScanModel: ObservableObject {
    enum Stage: Equatable { case idle, scanning, results, cleaning }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var progress: Double = 0      // 0…1
    @Published var currentLabel: String?
    @Published private(set) var groups: [ScanGroup] = []
    @Published var selection: Set<String> = []
    @Published var statusMessage: String?
    @Published private(set) var lastReport: RemovalReport?
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
    /// Appelé à la fin de chaque scan complet (espace sûr, espace détecté) : sert au planificateur.
    var onComplete: ((UInt64, UInt64) -> Void)?

    private enum LastScan {
        static let dateKey = "lastSmartScanDate"
        static let safeKey = "lastSmartScanSafeBytes"
        static func bytes(_ key: String, defaults: UserDefaults) -> UInt64 {
            (defaults.object(forKey: key) as? NSNumber)?.uint64Value ?? 0
        }
    }

    /// Lue à chaque scan : suit le réglage « Outils pour développeurs ».
    private let categorySource: () -> [CleaningCategory]
    private let defaults: UserDefaults
    private var categories: [CleaningCategory] { categorySource() }

    init(categories: @escaping () -> [CleaningCategory] = { ScanPreferences.currentCategories }, defaults: UserDefaults = .standard) {
        categorySource = categories
        self.defaults = defaults
        lastCompletedAt = defaults.object(forKey: LastScan.dateKey) as? Date
        lastSafeBytes = LastScan.bytes(LastScan.safeKey, defaults: defaults)
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
    var foundSize: UInt64 { allItems.reduce(0) { $0 + $1.size_bytes } }
    var foundCount: Int { allItems.count }
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
        lastReport = nil
        liveEntries = 0
        liveBytes = 0
        isComplete = false
        wasCancelled = false
        expectedEntries = [:]
        measuredEntries = [:]
        categoriesDone = 0
        categoryStartEntries = 0
    }

    func scan(keepReport: Bool = false) {
        guard !categories.isEmpty else {
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
        if !keepReport { lastReport = nil }

        let cats = categories
        let threshold = logThresholdKB
        let exclusions = userExclusions

        // Compteurs en direct, lus dans le moteur pendant qu'il travaille.
        Task { @MainActor in
            while self.generation == gen && self.stage == .scanning {
                let p = task.progress
                self.liveEntries = p.entries
                self.liveBytes = p.bytes
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
                    let group = ScanGroup(category: cat, items: items.sorted { $0.size_bytes > $1.size_bytes })
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
                    self.defaults.set(now, forKey: LastScan.dateKey)
                    self.defaults.set(NSNumber(value: safe), forKey: LastScan.safeKey)
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
        progress = max(progress, min(0.99, max(byCategory, estimate)))
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
        let ids = group.items.map(\.id)
        if isGroupFullySelected(group) { ids.forEach { selection.remove($0) } }
        else { selection.formUnion(ids) }
    }

    func selectAll() { selection = Set(allItems.map(\.id)) }
    func selectNone() { selection = [] }

    // MARK: Nettoyage

    /// Déplace vers la corbeille (ou supprime, selon le réglage) la sélection, re-validée
    /// par le moteur catégorie par catégorie — chaque catégorie avec sa propre racine de confinement.
    func cleanSelected() {
        let chosen = selectedItems
        guard !chosen.isEmpty else { return }
        stage = .cleaning
        statusMessage = nil

        let direct = directDelete
        let scannedCategories = groups.map(\.category)
        let rootByCategory = Dictionary(scannedCategories.map { ($0.category, $0.root) }, uniquingKeysWith: { first, _ in first })
        // Même règle (seuil et exclusions compris) que pour le scan : le moteur re-vérifie chaque élément.
        let threshold = logThresholdKB
        let exclusions = userExclusions
        let ruleByCategory = Dictionary(scannedCategories.map { cat -> (String, String) in
            let bytes: UInt64? = cat.usesThreshold ? UInt64(max(0, threshold)) * 1024 : nil
            return (cat.category, cat.ruleTOML(thresholdBytes: bytes, userExclusions: exclusions))
        }, uniquingKeysWith: { first, _ in first })
        let byCategory = Dictionary(grouping: chosen, by: \.category)

        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · nettoyage")
            defer { PowerAssertion.end(token) }

            var report = RemovalReport(direct: direct)
            do {
                for (cat, items) in byCategory {
                    guard let root = rootByCategory[cat] else { continue }
                    let input = PlanInput(
                        scope_root: root,
                        items: items.map { PlanItem(path: $0.path, identity: $0.identity) },
                        rule: ruleByCategory[cat]
                    )
                    if direct {
                        for r in try Engine.executeRemoval(input) {
                            if r.removed { report.removed += 1 }
                            else if !r.allowed { report.refused.append((r.path, r.refusal ?? "refusé")) }
                            else if let e = r.error { report.failed.append((r.path, e)) }
                        }
                    } else {
                        let decisions = try Engine.planRemoval(input)
                        let allowed = Set(decisions.filter(\.allowed).map(\.path))
                        for d in decisions where !d.allowed {
                            report.refused.append((d.path, d.refusal ?? "refusé"))
                        }
                        for item in items where allowed.contains(item.path) {
                            do {
                                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                                report.removed += 1
                            } catch {
                                report.failed.append((item.path, error.localizedDescription))
                            }
                        }
                    }
                }
                let final = report
                await MainActor.run {
                    self.lastReport = final
                    self.scan(keepReport: true)  // re-scan pour refléter ce qui reste
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = error.localizedDescription
                    self.stage = .results
                }
            }
        }
    }
}
