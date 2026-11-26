import Foundation
import MacCareMaintenance

struct UninstallFileOperations {
    var remove: (URL, Bool) throws -> Void = { url, direct in
        // Authorize before touching the contents of a package installed by another account.
        var info = stat()
        if lstat(url.path, &info) == 0, info.st_uid != getuid() { throw CocoaError(.fileWriteNoPermission) }
        if direct { try FileManager.default.removeItem(at: url) }
        else { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    }
    var authorize: ([ScanItem], AppInfo, Bool) async throws -> [AuthorizedUninstall.Result] = UninstallAuthorization.run

    static func requiresAuthorization(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSPOSIXErrorDomain { return [Int(EACCES), Int(EPERM)].contains(error.code) }
        if error.domain == NSCocoaErrorDomain && [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(error.code) { return true }
        return (error.userInfo[NSUnderlyingErrorKey] as? NSError).map(requiresAuthorization) ?? false
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
        var pending = [ScanItem]()

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
        func attempt(_ item: ScanItem) {
            do {
                try operations.remove(item.url, direct)
                report.removed += 1
            } catch where UninstallFileOperations.requiresAuthorization(error) {
                pending.append(item)
            } catch { report.failed.append((item.path, error.localizedDescription)) }
        }
        let keepReason = "Donnée conservée car l’application n’a pas été retirée."
        if let bundle {
            if validated(bundle, use: .application) { attempt(bundle) }
            if report.removed == 0 && pending.isEmpty {
                report.kept += data.map { ($0.path, keepReason) }
                return report
            }
        }
        let authorizeBundle = !pending.isEmpty
        if !data.isEmpty {
            let review = UninstallReview.current(for: app, artifacts: artifacts)
            for item in data where validated(item, use: review.use(of: item)) {
                if authorizeBundle { pending.append(item) }
                else { attempt(item) }
            }
        }
        guard !pending.isEmpty else { return report }
        do {
            let results = try await operations.authorize(pending, app, direct)
            for item in pending {
                guard let result = results.first(where: { $0.path == item.path }) else {
                    report.failed.append((item.path, "L’assistant n’a pas confirmé le retrait."))
                    continue
                }
                if result.kept { report.kept.append((item.path, result.error ?? keepReason)) }
                else if let error = result.error { report.failed.append((item.path, error)) }
                else { report.removed += 1 }
            }
        } catch {
            for item in pending {
                if authorizeBundle && item.path != bundle?.path { report.kept.append((item.path, keepReason)) }
                else { report.failed.append((item.path, error.localizedDescription)) }
            }
        }
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
