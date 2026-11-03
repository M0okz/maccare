import Foundation
import SwiftUI

/// Un emplacement de données de confidentialité régénérable (cache navigateur, vignettes…).
struct PrivacyEntry: Identifiable, Hashable {
    let tag: String
    let label: String
    let path: String
    var id: String { path }
}

enum PrivacyCatalog {
    private static func h(_ rel: String) -> String { (NSHomeDirectory() as NSString).appendingPathComponent(rel) }

    /// Caches de navigateurs et de vignettes. On ne touche jamais aux cookies, mots de passe ni
    /// à l'historique (déconnexions, pertes de session) : seulement des caches régénérables.
    static let entries: [PrivacyEntry] = [
        .init(tag: "Chrome", label: "Cache Google Chrome", path: h("Library/Caches/Google/Chrome")),
        .init(tag: "Brave", label: "Cache Brave", path: h("Library/Caches/BraveSoftware")),
        .init(tag: "Edge", label: "Cache Microsoft Edge", path: h("Library/Caches/Microsoft Edge")),
        .init(tag: "Firefox", label: "Cache Firefox", path: h("Library/Caches/Firefox")),
        .init(tag: "Arc", label: "Cache Arc", path: h("Library/Caches/company.thebrowser.Browser")),
        .init(tag: "Opera", label: "Cache Opera", path: h("Library/Caches/com.operasoftware.Opera")),
        .init(tag: "Vivaldi", label: "Cache Vivaldi", path: h("Library/Caches/Vivaldi")),
        .init(tag: "Safari", label: "Cache Safari", path: h("Library/Caches/com.apple.Safari")),
        .init(tag: "QuickLook", label: "Vignettes QuickLook", path: h("Library/Caches/com.apple.QuickLook.thumbnailcache")),
        .init(tag: "Système", label: "État d'app enregistré (restauration de fenêtres)", path: h("Library/Saved Application State")),
        .init(tag: "Rapports", label: "Rapports de diagnostic (utilisateur)", path: h("Library/Logs/DiagnosticReports")),
    ]
}

/// Repère les caches de confidentialité existants et met la sélection à la corbeille, confinée
/// au dossier personnel et re-validée par les gardes de sûreté.
@MainActor
final class PrivacyModel: ObservableObject {
    @Published private(set) var items: [ScanItem] = []
    @Published var selection: Set<String> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published var statusMessage: String?
    @Published var lastReport: RemovalReport?
    @Published private(set) var hasScanned = false

    @Published private(set) var scanFailed = false
    private let inspect: @Sendable ([String]) throws -> [ScanItem]

    init(inspect: @escaping @Sendable ([String]) throws -> [ScanItem] = { try Engine.inspectPaths($0, category: "privacy") }) {
        self.inspect = inspect
    }

    private let scopeRoot = NSHomeDirectory()
    private var directDelete: Bool { UserDefaults.standard.bool(forKey: "directDelete") }

    var directDeleteEnabled: Bool { directDelete }
    var selectedItems: [ScanItem] { items.filter { selection.contains($0.id) } }
    var selectedSize: UInt64 { selectedItems.reduce(0) { $0 + $1.size_bytes } }
    var totalSize: UInt64 { items.reduce(0) { $0 + $1.size_bytes } }

    func tag(for item: ScanItem) -> String { PrivacyCatalog.entries.first { $0.path == item.path }?.tag ?? "cache" }
    func label(for item: ScanItem) -> String { PrivacyCatalog.entries.first { $0.path == item.path }?.label ?? item.displayName }

    func scan(keepReport: Bool = false) {
        guard !isScanning && !isCleaning else { return }
        isScanning = true
        scanFailed = false
        statusMessage = nil
        if !keepReport { lastReport = nil }
        let candidates = PrivacyCatalog.entries.map(\.path)
        let inspect = self.inspect
        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · confidentialité")
            defer { PowerAssertion.end(token) }
            let result: Result<[ScanItem], Error>
            do {
                result = .success(try inspect(candidates))
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                switch result {
                case .success(let found):
                    // Un emplacement vide (ou illisible faute d'accès) n'a rien à proposer : on le masque.
                    self.items = found.filter { $0.size_bytes > 0 }.sorted { $0.size_bytes > $1.size_bytes }
                    self.selection = []
                case .failure(let err):
                    self.items = []
                    self.scanFailed = true
                    self.selection = []
                    self.statusMessage = err.localizedDescription
                }
                self.isScanning = false
                self.hasScanned = true
            }
        }
    }

    func toggle(_ item: ScanItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }
    func selectAll() { selection = Set(items.map(\.id)) }
    func selectNone() { selection = [] }

    func cleanSelected(directOverride: Bool? = nil) {
        let chosen = selectedItems
        guard !isScanning && !isCleaning && !chosen.isEmpty else { return }
        isCleaning = true
        statusMessage = nil
        let input = PlanInput(scope_root: scopeRoot, items: chosen.map { PlanItem(path: $0.path, identity: $0.identity) })
        let direct = directOverride ?? directDelete

        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · confidentialité")
            defer { PowerAssertion.end(token) }
            let outcome: Result<RemovalReport, Error> = {
                var report = RemovalReport(direct: direct)
                do {
                    if direct {
                        for r in try Engine.executeRemoval(input) {
                            if r.removed { report.removed += 1 }
                            else if !r.allowed { report.refused.append((r.path, r.refusal ?? "refusé")) }
                            else if let e = r.error { report.failed.append((r.path, e)) }
                        }
                    } else {
                        let decisions = try Engine.planRemoval(input)
                        let allowed = Set(decisions.filter(\.allowed).map(\.path))
                        for d in decisions where !d.allowed { report.refused.append((d.path, d.refusal ?? "refusé")) }
                        for item in chosen where allowed.contains(item.path) {
                            do { try FileManager.default.trashItem(at: item.url, resultingItemURL: nil); report.removed += 1 }
                            catch { report.failed.append((item.path, error.localizedDescription)) }
                        }
                    }
                    return .success(report)
                } catch { return .failure(error) }
            }()
            await MainActor.run {
                switch outcome {
                case .success(let report): self.lastReport = report; self.isCleaning = false; self.scan(keepReport: true)
                case .failure(let err): self.statusMessage = err.localizedDescription; self.isCleaning = false
                }
            }
        }
    }
}

/// Le catalogue contient aussi des données locales autres que celles des navigateurs.
enum PrivacyGroup: String, CaseIterable, Identifiable {
    case browsers, local
    var id: String { rawValue }
    var title: String { self == .browsers ? "Navigateurs" : "Autres données locales" }
    var detail: String {
        self == .browsers ? "Fichiers temporaires des navigateurs. Les premiers chargements pourront être plus lents."
            : "Aperçus, rapports de diagnostic et état des fenêtres. Examinez chaque catégorie avant de la retirer."
    }
    func contains(_ item: ScanItem) -> Bool {
        let tag = PrivacyCatalog.entries.first { $0.path == item.path }?.tag
        let local = tag == "QuickLook" || tag == "Système" || tag == "Rapports" || tag == nil
        return self == .local ? local : !local
    }
    func items(in items: [ScanItem]) -> [ScanItem] { items.filter(contains) }
}
