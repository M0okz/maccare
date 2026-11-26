import Foundation
import MacCareMaintenance

/// Opérations de fichiers du désinstalleur, remplaçables dans les tests.
///
/// Deux refus de macOS se ressemblent mais n’ont pas le même remède :
/// - un élément d’un autre compte, ou un dossier parent non inscriptible, relève des droits
///   POSIX : l’autorisation administrateur y remédie ;
/// - un élément de la session dans un dossier inscriptible relève de la confidentialité de
///   macOS (conteneurs d’apps, TCC). Root y est soumis aussi : seul l’Accès complet au disque
///   accordé à MacCare permet ce retrait, sans autorisation administrateur.
struct UninstallFileOperations {
    var remove: (URL, Bool) throws -> Void = { url, direct in
        if direct { try FileManager.default.removeItem(at: url) }
        else { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    }
    /// Un paquet installé par l’App Store ou un composant de `/Library` appartient à root.
    var ownedByUser: (URL) -> Bool = { url in
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_uid == getuid()
    }
    var parentWritable: (URL) -> Bool = { url in
        access(url.deletingLastPathComponent().path, W_OK | X_OK) == 0
    }
    var fullDiskAccess: () -> PermissionState = { FullDiskAccess.state() }
    var authorize: ([ScanItem], AppInfo, Bool) async throws -> [AuthorizedUninstall.Result] = UninstallAuthorization.run

    /// Refus d’accès, quelle qu’en soit la cause (POSIX, Cocoa ou `afpAccessDenied`).
    static func isAccessDenial(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSPOSIXErrorDomain { return [Int(EACCES), Int(EPERM)].contains(error.code) }
        if error.domain == NSCocoaErrorDomain && [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(error.code) { return true }
        if error.domain == NSOSStatusErrorDomain && error.code == -5000 { return true }
        return (error.userInfo[NSUnderlyingErrorKey] as? NSError).map(isAccessDenial) ?? false
    }

    /// Conteneurs gérés par macOS : leur racine n’est déplaçable qu’avec l’Accès complet au disque.
    static func isAppContainer(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent().lastPathComponent
        return url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Library"
            && ["Containers", "Group Containers"].contains(parent)
    }

    static func protectionMessage(for url: URL, fullDisk: PermissionState) -> String {
        if fullDisk == .granted {
            return "macOS refuse ce déplacement malgré l’Accès complet au disque : l’élément est verrouillé ou réservé au système."
        }
        if url.pathExtension == "app" {
            return "macOS protège ce paquet. Autorisez MacCare dans Réglages Système › Confidentialité et sécurité › Gestion des apps, puis relancez le retrait."
        }
        let subject = isAppContainer(url) ? "macOS protège les conteneurs des applications." : "macOS protège cet emplacement."
        return subject + " Accordez l’Accès complet au disque à MacCare, puis relancez le retrait. L’autorisation administrateur ne suffit pas."
    }
}

extension Remover {
    static func uninstall(_ items: [ScanItem], app: AppInfo, direct: Bool, operations: UninstallFileOperations = .init(),
                          artifacts supplied: UninstallArtifacts? = nil) async throws -> RemovalReport {
        let bundlePath = app.url.standardizedFileURL.path
        let root = app.url.deletingLastPathComponent().standardizedFileURL.path
        guard app.url.pathExtension == "app", AppCatalog.applicationDirectories.contains(root),
              !AppCatalog.isProtectedApplication(app.url) else {
            throw Engine.EngineError.engine("Cette application est protégée ou située hors des dossiers Applications.")
        }
        let bundle = items.first { $0.url.standardizedFileURL.path == bundlePath }
        let data = items.filter { $0.url.standardizedFileURL.path != bundlePath }
        let artifacts = supplied ?? UninstallArtifacts(app: app)
        var report = RemovalReport(direct: direct)
        var fullDisk: PermissionState?
        let keepReason = "Donnée conservée car l’application n’a pas été retirée."

        func validated(_ item: ScanItem, use: UninstallDataUse?) -> Bool {
            guard let use, use.canRemove else {
                report.refused.append((item.path, use?.reason ?? "Ce fichier n’appartient plus à l’application."))
                return false
            }
            do {
                let decision = try Engine.planRemoval(uninstallPlan(for: item, use: use)).first
                guard decision?.allowed == true, decision?.path == item.path else {
                    report.refused.append((item.path, decision?.refusal ?? "Chemin non validé."))
                    return false
                }
                return true
            } catch { report.failed.append((item.path, error.localizedDescription)); return false }
        }
        enum Attempt { case removed, needsAdministrator, failed }
        /// Retrait avec les droits de la session ; root n’est sollicité que pour les droits POSIX.
        func attempt(_ item: ScanItem) -> Attempt {
            guard operations.ownedByUser(item.url) else { return .needsAdministrator }
            do {
                try operations.remove(item.url, direct)
                report.removed += 1
                return .removed
            } catch where UninstallFileOperations.isAccessDenial(error) {
                if !operations.parentWritable(item.url) { return .needsAdministrator }
                let state = fullDisk ?? operations.fullDiskAccess()
                fullDisk = state
                report.failed.append((item.path, UninstallFileOperations.protectionMessage(for: item.url, fullDisk: state)))
            } catch { report.failed.append((item.path, error.localizedDescription)) }
            return .failed
        }
        /// Une autorisation pour un lot ; vrai si le paquet du lot a bien été retiré.
        func authorize(_ batch: [ScanItem]) async -> Bool {
            let withBundle = batch.contains { $0.path == bundle?.path }
            do {
                let results = try await operations.authorize(batch, app, direct)
                var bundleRemoved = false
                for item in batch {
                    guard let result = results.first(where: { $0.path == item.path }) else {
                        report.failed.append((item.path, "L’assistant n’a pas confirmé le retrait."))
                        continue
                    }
                    if result.kept { report.kept.append((item.path, result.error ?? keepReason)) }
                    else if let error = result.error { report.failed.append((item.path, error)) }
                    else {
                        report.removed += 1
                        if item.path == bundle?.path { bundleRemoved = true }
                    }
                }
                return bundleRemoved
            } catch {
                for item in batch {
                    if withBundle && item.path != bundle?.path { report.kept.append((item.path, keepReason)) }
                    else { report.failed.append((item.path, error.localizedDescription)) }
                }
                return false
            }
        }

        let review = data.isEmpty ? nil : UninstallReview.current(for: app, artifacts: artifacts)
        // Les éléments d’un autre compte partent avec le paquet, sous la même autorisation.
        let foreign = data.filter { !operations.ownedByUser($0.url) }
        let local = data.filter { operations.ownedByUser($0.url) }
        var elevated = [ScanItem]()

        if let bundle {
            guard validated(bundle, use: .application) else {
                report.kept += data.map { ($0.path, keepReason) }
                return report
            }
            switch attempt(bundle) {
            case .removed:
                elevated = foreign.filter { validated($0, use: review?.use(of: $0)) }
            case .failed:
                report.kept += data.map { ($0.path, keepReason) }
                return report
            case .needsAdministrator:
                let batch = [bundle] + foreign.filter { validated($0, use: review?.use(of: $0)) }
                guard await authorize(batch) else {
                    report.kept += local.map { ($0.path, keepReason) }
                    return report
                }
            }
        } else {
            elevated = foreign.filter { validated($0, use: review?.use(of: $0)) }
        }
        // Validation après l’éventuel dialogue : l’identité est revérifiée au plus près du retrait.
        for item in local where validated(item, use: review?.use(of: item)) {
            if attempt(item) == .needsAdministrator { elevated.append(item) }
        }
        if !elevated.isEmpty { _ = await authorize(elevated) }
        return report
    }

    private static func uninstallPlan(for item: ScanItem, use: UninstallDataUse) throws -> PlanInput {
        let parent = item.url.deletingLastPathComponent().path
        var plan = PlanInput(scope_root: parent, items: [.init(path: item.path, identity: item.identity)])
        guard use == .application || use == .machine else { return plan }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        func quote(_ value: String) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
        plan.rule = """
        id = "uninstall.selected-application"
        category = "uninstall"
        version = 1
        root = \(try quote(parent))
        depth = "per-app"
        [[include]]
        kind = "name-suffix"
        ends_with = \(try quote(item.url.lastPathComponent))
        """
        return plan
    }
}
