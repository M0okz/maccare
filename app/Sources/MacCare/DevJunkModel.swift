import Foundation
import SwiftUI

/// Un emplacement connu de « déchets de développement » : un cache régénérable à un chemin fixe.
/// On ne liste QUE des caches re-téléchargeables ou reconstructibles — jamais un état non
/// régénérable (disques de VM colima/Docker, DeviceSupport actifs, dépôts source).
struct DevJunkEntry: Identifiable, Hashable {
    let tool: String      // étiquette courte (badge)
    let label: String     // description lisible
    let path: String      // chemin absolu (développé)
    var id: String { path }
}

enum DevJunkCatalog {
    private static let home = NSHomeDirectory()
    private static func h(_ rel: String) -> String { (home as NSString).appendingPathComponent(rel) }

    /// Caches de dev à des emplacements fixes. Rien n'est vérifié ici : `inspectPaths` ne
    /// gardera que ceux qui existent réellement.
    static let entries: [DevJunkEntry] = [
        // Build / dérivés
        .init(tool: "Xcode", label: "DerivedData (artefacts de build reconstruits)",
              path: h("Library/Developer/Xcode/DerivedData")),
        .init(tool: "Xcode", label: "Caches du simulateur",
              path: h("Library/Developer/CoreSimulator/Caches")),
        .init(tool: "Swift PM", label: "Cache des paquets Swift",
              path: h("Library/Caches/org.swift.swiftpm")),
        .init(tool: "Go", label: "Cache de build (go-build)",
              path: h("Library/Caches/go-build")),
        // Caches de dépendances (re-téléchargés à la demande)
        .init(tool: "Go", label: "Cache de modules (go/pkg/mod)",
              path: h("go/pkg/mod")),
        .init(tool: "Cargo", label: "Cache du registre (.cargo/registry/cache)",
              path: h(".cargo/registry/cache")),
        .init(tool: "Cargo", label: "Checkouts git (.cargo/git)",
              path: h(".cargo/git")),
        .init(tool: "npm", label: "Cache npm (_cacache)",
              path: h(".npm/_cacache")),
        .init(tool: "Yarn", label: "Cache Yarn",
              path: h("Library/Caches/Yarn")),
        .init(tool: "pip", label: "Cache pip",
              path: h("Library/Caches/pip")),
        .init(tool: "Gradle", label: "Caches Gradle",
              path: h(".gradle/caches")),
        .init(tool: "Maven", label: "Dépôt local (.m2/repository)",
              path: h(".m2/repository")),
        // Caches d'outils
        .init(tool: "Homebrew", label: "Cache des téléchargements Homebrew",
              path: h("Library/Caches/Homebrew")),
        .init(tool: "CocoaPods", label: "Cache CocoaPods",
              path: h("Library/Caches/CocoaPods")),
        .init(tool: "Carthage", label: "Cache Carthage",
              path: h("Library/Caches/org.carthage.CarthageKit")),
        .init(tool: "Playwright", label: "Navigateurs Playwright",
              path: h("Library/Caches/ms-playwright")),
        .init(tool: "Puppeteer", label: "Navigateurs Puppeteer",
              path: h(".cache/puppeteer")),
        .init(tool: "Electron", label: "Cache Electron",
              path: h("Library/Caches/electron")),
        .init(tool: "Electron", label: "Cache electron-builder",
              path: h("Library/Caches/electron-builder")),
    ]
}

/// Scanne les emplacements du catalogue Dev junk, présente ceux qui existent avec leur taille,
/// et met à la corbeille la sélection (confinée au dossier personnel, re-validée par les gardes).
@MainActor
final class DevJunkModel: ObservableObject {
    @Published private(set) var items: [ScanItem] = []
    @Published var selection: Set<String> = []
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published var statusMessage: String?
    @Published var lastReport: RemovalReport?
    @Published private(set) var hasScanned = false

    private let scopeRoot = NSHomeDirectory()
    private var directDelete: Bool { UserDefaults.standard.bool(forKey: "directDelete") }

    var directDeleteEnabled: Bool { directDelete }
    var selectedItems: [ScanItem] { items.filter { selection.contains($0.id) } }
    var selectedSize: UInt64 { selectedItems.reduce(0) { $0 + $1.size_bytes } }
    var totalSize: UInt64 { items.reduce(0) { $0 + $1.size_bytes } }

    /// Étiquette d'outil pour un élément (via son chemin dans le catalogue).
    func tool(for item: ScanItem) -> String {
        DevJunkCatalog.entries.first { $0.path == item.path }?.tool ?? "dev"
    }
    func label(for item: ScanItem) -> String {
        DevJunkCatalog.entries.first { $0.path == item.path }?.label ?? item.displayName
    }

    func scan(keepReport: Bool = false) {
        isScanning = true
        statusMessage = nil
        if !keepReport { lastReport = nil }
        let candidates = DevJunkCatalog.entries.map(\.path)
        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · dev junk")
            defer { PowerAssertion.end(token) }
            let result: Result<[ScanItem], Error>
            do {
                result = .success(try Engine.inspectPaths(candidates, category: "dev-junk"))
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                switch result {
                case .success(let found):
                    // Un emplacement vide n'a rien à récupérer : on ne l'affiche pas.
                    self.items = found.filter { $0.size_bytes > 0 }.sorted { $0.size_bytes > $1.size_bytes }
                    self.selection = []
                case .failure(let err):
                    self.items = []
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

    func cleanSelected() {
        let chosen = selectedItems
        guard !chosen.isEmpty else { return }
        isCleaning = true
        statusMessage = nil

        let input = PlanInput(
            scope_root: scopeRoot,
            items: chosen.map { PlanItem(path: $0.path, identity: $0.identity) }
        )
        let direct = directDelete

        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · dev junk")
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
