import Foundation
import SwiftUI

/// Compte-rendu d'une opération de suppression, pour affichage.
struct RemovalReport {
    var direct: Bool
    var removed: Int = 0
    var refused: [(path: String, reason: String)] = []
    var failed: [(path: String, error: String)] = []
}

@MainActor
final class ReviewModel: ObservableObject {
    private enum Keys {
        static let directDelete = "directDelete"
        static let thresholdKB = "logThresholdKB"
        static let exclusions = "userExclusions"
    }

    @Published var category: CleaningCategory = CleaningCategory.visible.first ?? CleaningCategory.all[0] {
        didSet { if oldValue != category { reset() } }
    }
    @Published private(set) var items: [ScanItem] = []
    @Published var selection: Set<String> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published var statusMessage: String?
    @Published var lastReport: RemovalReport?

    // Réglages persistés.
    @Published var directDelete: Bool { didSet { defaults.set(directDelete, forKey: Keys.directDelete) } }
    @Published var logThresholdKB: Int { didSet { defaults.set(logThresholdKB, forKey: Keys.thresholdKB) } }
    @Published private(set) var userExclusions: [String] {
        didSet { defaults.set(userExclusions, forKey: Keys.exclusions) }
    }

    private let defaults = UserDefaults.standard

    init() {
        directDelete = defaults.bool(forKey: Keys.directDelete)
        logThresholdKB = (defaults.object(forKey: Keys.thresholdKB) as? NSNumber)?.intValue ?? 10
        userExclusions = defaults.stringArray(forKey: Keys.exclusions) ?? []
    }

    var engineVersion: String { Engine.version }
    var categories: [CleaningCategory] { CleaningCategory.visible }
    var selectedItems: [ScanItem] { items.filter { selection.contains($0.id) } }
    var selectedSize: UInt64 { selectedItems.reduce(0) { $0 + $1.size_bytes } }
    var totalSize: UInt64 { items.reduce(0) { $0 + $1.size_bytes } }

    private var thresholdBytes: UInt64? {
        category.usesThreshold ? UInt64(max(0, logThresholdKB)) * 1024 : nil
    }

    private func reset() {
        items = []
        selection = []
        statusMessage = nil
        lastReport = nil
    }

    /// Ajoute un chemin aux exclusions personnalisées et relance un scan.
    func exclude(_ item: ScanItem) {
        if !userExclusions.contains(item.path) {
            userExclusions.append(item.path)
        }
        scan()
    }

    func addExclusion(_ path: String) {
        guard !userExclusions.contains(path) else { return }
        userExclusions.append(path)
    }

    func removeExclusion(_ path: String) {
        userExclusions.removeAll { $0 == path }
    }

    func clearExclusions() {
        userExclusions = []
    }

    /// Lance un scan. N'altère rien sur le disque.
    func scan(keepReport: Bool = false) {
        isScanning = true
        statusMessage = nil
        if !keepReport { lastReport = nil }
        let rule = category.ruleTOML(thresholdBytes: thresholdBytes, userExclusions: userExclusions)
        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · scan")
            defer { PowerAssertion.end(token) }
            let result: Result<[ScanItem], Error>
            do {
                result = .success(try Engine.scan(ruleTOML: rule))
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                switch result {
                case .success(let found):
                    self.items = found.sorted { $0.size_bytes > $1.size_bytes }
                    self.selection = []
                case .failure(let err):
                    self.items = []
                    self.statusMessage = err.localizedDescription
                }
                self.isScanning = false
            }
        }
    }

    /// Valide la sélection via le moteur, puis la met à la corbeille — ou la supprime
    /// directement si le mode explicite est activé. Dans les deux cas, seuls les éléments
    /// autorisés par les gardes sont touchés.
    func cleanSelected() {
        let chosen = selectedItems
        guard !chosen.isEmpty else { return }
        isCleaning = true
        statusMessage = nil

        let input = PlanInput(
            scope_root: category.root,
            items: chosen.map { PlanItem(path: $0.path, identity: $0.identity) },
            rule: category.ruleTOML(thresholdBytes: thresholdBytes, userExclusions: userExclusions)
        )
        let direct = directDelete

        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · nettoyage")
            defer { PowerAssertion.end(token) }
            let outcome: Result<RemovalReport, Error> = {
                var report = RemovalReport(direct: direct)
                do {
                    if direct {
                        let results = try Engine.executeRemoval(input)
                        for r in results {
                            if r.removed {
                                report.removed += 1
                            } else if !r.allowed {
                                report.refused.append((r.path, r.refusal ?? "refusé"))
                            } else if let e = r.error {
                                report.failed.append((r.path, e))
                            }
                        }
                    } else {
                        let decisions = try Engine.planRemoval(input)
                        let allowed = Set(decisions.filter(\.allowed).map(\.path))
                        for d in decisions where !d.allowed {
                            report.refused.append((d.path, d.refusal ?? "refusé"))
                        }
                        for item in chosen where allowed.contains(item.path) {
                            do {
                                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                                report.removed += 1
                            } catch {
                                report.failed.append((item.path, error.localizedDescription))
                            }
                        }
                    }
                    return .success(report)
                } catch {
                    return .failure(error)
                }
            }()

            await MainActor.run {
                switch outcome {
                case .success(let report):
                    self.lastReport = report
                    self.isCleaning = false
                    self.scan(keepReport: true)
                case .failure(let err):
                    self.statusMessage = err.localizedDescription
                    self.isCleaning = false
                }
            }
        }
    }
}

/// Formatage lisible d'une taille en octets, en unités françaises (o, Ko, Mo, Go, To) et en
/// base 1000 comme le Finder. Virgule décimale, espace insécable avant l'unité.
func humanSize(_ bytes: UInt64) -> String {
    let units = ["o", "Ko", "Mo", "Go", "To"]
    var value = Double(bytes)
    var unit = 0
    while value >= 1000, unit < units.count - 1 {
        value /= 1000
        unit += 1
    }
    let decimals = unit <= 1 ? 0 : (value < 100 ? 2 : 1)
    var text = String(format: "%.\(decimals)f", value)
    if text.contains(".") {
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
    }
    return "\(text.replacingOccurrences(of: ".", with: ","))\u{00A0}\(units[unit])"
}
