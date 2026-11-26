import Foundation
import SwiftUI

@MainActor
final class UninstallModel: ObservableObject {
    @Published private(set) var apps: [AppInfo] = []
    @Published var selectedApp: AppInfo? {
        didSet { if oldValue != selectedApp { scanResiduals() } }
    }
    @Published private(set) var residuals: [ScanItem] = []
    @Published private(set) var review: UninstallReview?
    @Published var selection: Set<String> = []
    private var scanGeneration = 0
    private var artifacts: UninstallArtifacts?
    @Published private(set) var receipt: UninstallReceipt?
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published var statusMessage: String?
    @Published var lastReport: RemovalReport?

    /// Les résidus d’applications déjà supprimées restent dans le dossier personnel.
    /// Le paquet installé utilise son propre périmètre dans Remover.uninstall.
    private let scopeRoot = NSHomeDirectory()

    private var directDelete: Bool { UserDefaults.standard.bool(forKey: "directDelete") }

    var directDeleteEnabled: Bool { directDelete }
    var selectedItems: [ScanItem] { residuals.filter { selection.contains($0.id) && review?.use(of: $0)?.canRemove == true } }
    var selectedSize: UInt64 { selectedItems.reduce(0) { $0 + $1.size_bytes } }
    var totalSize: UInt64 { residuals.reduce(0) { $0 + $1.size_bytes } }

    func loadApps() {
        if apps.isEmpty { apps = AppCatalog.installedApps() }
    }

    /// Inventaire rafraîchi à la demande, hors du thread d’interface.
    func refreshApps() async {
        apps = await Task.detached(priority: .userInitiated) { AppCatalog.installedApps() }.value
    }

    func scanResiduals(keepReport: Bool = false) {
        scanGeneration += 1
        let generation = scanGeneration
        review = nil
        residuals = []
        selection = []
        if !keepReport { artifacts = nil; receipt = nil; lastReport = nil }
        let prior = artifacts
        guard let app = selectedApp else {
            isScanning = false
            return
        }
        isScanning = true
        statusMessage = nil
        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · désinstalleur")
            defer { PowerAssertion.end(token) }
            let metadata = prior ?? UninstallArtifacts(app: app)
            let review = UninstallReview.current(for: app, artifacts: metadata)
            let result: Result<[ScanItem], Error>
            do {
                result = .success(try Engine.inspectPaths(Array(review.candidates.keys)))
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                guard self.scanGeneration == generation else { return }
                switch result {
                case .success(let found):
                    self.residuals = found.sorted { $0.size_bytes > $1.size_bytes }
                    self.review = review
                    self.artifacts = metadata
                    self.selection = Set(found.filter { review.use(of: $0)?.preselected == true }.map(\.id))
                case .failure(let err):
                    self.residuals = []
                    self.statusMessage = err.localizedDescription
                }
                self.isScanning = false
            }
        }
    }

    // MARK: Restes d'applications déjà supprimées

    @Published private(set) var leftovers: [LeftoverItem] = []
    @Published var leftoverSelection: Set<String> = []
    @Published private(set) var isScanningLeftovers = false
    @Published private(set) var leftoversScanned = false
    /// Affiche l'écran des restes plutôt que la grille d'applications.
    @Published var showingLeftovers = false
    @Published var leftoverReport: RemovalReport?

    var leftoverTotal: UInt64 { leftovers.reduce(0) { $0 + $1.item.size_bytes } }
    var leftoverSelectedItems: [LeftoverItem] { leftovers.filter { leftoverSelection.contains($0.id) } }
    var leftoverSelectedSize: UInt64 { leftoverSelectedItems.reduce(0) { $0 + $1.item.size_bytes } }

    func scanLeftovers() {
        guard !isScanningLeftovers else { return }
        isScanningLeftovers = true
        Task.detached(priority: .utility) {
            let token = PowerAssertion.beginUserActivity("MacCare · restes d'apps")
            defer { PowerAssertion.end(token) }
            let found = LeftoverScanner.scan()
            await MainActor.run {
                self.leftovers = found
                self.leftoverSelection = []
                self.isScanningLeftovers = false
                self.leftoversScanned = true
            }
        }
    }

    /// Met la sélection à la corbeille (jamais présélectionnée), validée par le moteur.
    func cleanLeftovers() {
        let chosen = leftoverSelectedItems.map(\.item)
        guard !chosen.isEmpty else { return }
        isCleaning = true
        statusMessage = nil
        let direct = directDelete
        let scope = scopeRoot
        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · restes d'apps")
            defer { PowerAssertion.end(token) }
            let outcome: Result<RemovalReport, Error>
            do {
                outcome = .success(try Remover.remove(chosen, scopeRoot: scope, direct: direct))
            } catch {
                outcome = .failure(error)
            }
            await MainActor.run {
                switch outcome {
                case .success(let report):
                    self.leftoverReport = report
                    self.isCleaning = false
                    self.scanLeftovers()
                case .failure(let err):
                    self.statusMessage = err.localizedDescription
                    self.isCleaning = false
                }
            }
        }
    }

    func cleanSelected() {
        let chosen = selectedItems
        guard !chosen.isEmpty, !isCleaning, !isScanning, let app = selectedApp else { return }
        isCleaning = true
        statusMessage = nil

        let direct = directDelete
        let inventory = residuals
        let reviewed = review
        let metadata = artifacts

        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · désinstalleur")
            defer { PowerAssertion.end(token) }
            let outcome: Result<RemovalReport, Error>
            do { outcome = .success(try await Remover.uninstall(chosen, app: app, direct: direct, artifacts: metadata)) }
            catch { outcome = .failure(error) }

            await MainActor.run {
                switch outcome {
                case .success(let report):
                    self.receipt = UninstallReceipt(app: app, inventory: inventory, chosen: chosen, review: reviewed, report: report)
                    self.lastReport = report
                    if !FileManager.default.fileExists(atPath: app.url.path) { self.apps.removeAll { $0.id == app.id } }
                    self.isCleaning = false
                    self.scanResiduals(keepReport: true)
                case .failure(let err):
                    self.statusMessage = err.localizedDescription
                    self.isCleaning = false
                }
            }
        }
    }
}
