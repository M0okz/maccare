import Foundation
import AppKit
import Combine
import Sparkle

@MainActor
final class ApplicationUpdateInstaller: NSObject, ObservableObject, @MainActor SPUUpdaterDelegate, @MainActor SPUStandardUserDriverDelegate {
    enum Phase: Equatable {
        case preparing, downloading(Double?), verifying, installing, sparkle, waitingForInstaller, completed, cancelled, deferred, failed(String)
        var message: String {
            switch self {
            case .preparing: return "Préparation de la mise à jour…"
            case .downloading: return "Téléchargement de la nouvelle version…"
            case .verifying: return "Vérification de l’application et de son éditeur…"
            case .installing: return "Installation en cours…"
            case .sparkle: return "Poursuivez la mise à jour dans le panneau de l’application."
            case .waitingForInstaller: return "Terminez l’installateur macOS, puis vérifiez l’installation."
            case .completed: return "Mise à jour installée."
            case .cancelled: return "Mise à jour annulée."
            case .deferred: return "La mise à jour a été reportée dans le panneau de l’application."
            case .failed(let reason): return reason
            }
        }
    }

    @Published private(set) var states: [String: Phase] = [:]
    @Published private(set) var activeID: String?
    @Published private(set) var lastCompletedID: String?
    @Published private(set) var lastResult: String?
    private var task: Task<Void, Never>?
    private var externalUpdater: SPUUpdater?
    private var pending: [String: PreparedApplicationUpdate] = [:]
    private var activeTarget: ApplicationUpdateTarget?
    private var activeName: String?
    var isBusy: Bool { activeID != nil }
    var canCancel: Bool {
        guard let activeID else { return false }
        switch states[activeID] { case .preparing, .downloading, .verifying: return true; default: return false }
    }

    func unavailableReason(for entry: ApplicationUpdateEntry, apps: [AppInfo]) -> String? {
        if entry.source.key == "mas" {
            if entry.item.storeID == nil { return "L’identifiant App Store de cette mise à jour est indisponible." }
            if AppBuildIdentity.isDevelopment { return "La mise à jour App Store nécessite la version distribuée de MacCare, signée Developer ID." }
        }
        guard let url = entry.applicationURL(in: apps), let expected = entry.versions?.available else {
            return "L’application installée ne peut pas être identifiée."
        }
        guard let target = try? ApplicationUpdatePolicy().target(url: url, expectedVersion: expected) else {
            return "Actualisez la liste : la version ou l’emplacement de l’application a changé."
        }
        if entry.source.key == "mas" || sparkleBundle(target.url) != nil || entry.item.artifact != nil || entry.source.key == "cask" { return nil }
        return "Cette application ne fournit pas encore d’archive ou de flux compatible."
    }

    func requiresQuit(_ entry: ApplicationUpdateEntry, apps: [AppInfo]) -> Bool {
        guard let url = entry.applicationURL(in: apps) else { return false }
        return sparkleBundle(url) == nil && Self.isRunning(url)
    }

    func install(_ entry: ApplicationUpdateEntry, apps: [AppInfo], quitIfRunning: Bool = false) {
        guard !isBusy else { return }
        if let reason = unavailableReason(for: entry, apps: apps) { states[entry.id] = .failed(reason); return }
        let id = entry.id;activeID = id; activeName = entry.item.name;states[id] = .preparing;lastResult = nil
        let url = entry.applicationURL(in: apps)
        task = Task { [self] in
            do {
                if quitIfRunning, let url { try await Self.quitNormally(url) }
                if entry.source.key == "mas", let storeID = entry.item.storeID {
                    guard let tool = AppStoreUpdates.executableURL(in: Bundle.main.bundleURL) else { throw ApplicationUpdateFailure.refused("Le composant App Store est absent du paquet MacCare.") }
                    guard let url, let expected = entry.versions?.available else { throw ApplicationUpdateFailure.refused("L’application installée est introuvable.") }
                    let target = try ApplicationUpdatePolicy().target(url: url, expectedVersion: expected)
                    states[id] = .installing
                    let script = try ApplicationUpdateCommand.appStoreAuthorizationScript(executable: tool, id: storeID)
                    _ = try await ApplicationUpdateCommand.run("/usr/bin/osascript", ["-e", script])
                    try ApplicationUpdatePolicy().validateCandidate(at: target.url, target: target)
                    finish(id, name: entry.item.name)
                    return
                }
                var target: ApplicationUpdateTarget?
                if let url, let expected = entry.versions?.available {
                    target = try ApplicationUpdatePolicy().target(url: url, expectedVersion: expected)
                    if let target, let bundle = sparkleBundle(target.url) {
                        activeTarget = target
                        try beginSparkle(bundle: bundle, id: id)
                        return
                    }
                    guard !Self.isRunning(url) else { throw ApplicationUpdateFailure.refused("Quittez \(entry.item.name), puis cliquez à nouveau sur Mettre à jour. Aucun arrêt forcé n’est effectué.") }
                }
                let token = entry.item.catalogToken ?? (entry.source.key == "cask" ? entry.item.name : nil)
                if let token, ApplicationUpdatePolicy.validToken(token), let brew = SystemTools.locate("brew") {
                    let caskDirectory = URL(fileURLWithPath: brew).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Caskroom").appendingPathComponent(token)
                    if let target, ApplicationUpdatePolicy.managedCaskMatches(directory: caskDirectory, target: target.url) {
                        try Task.checkCancellation(); states[id] = .installing
                        _ = try await ApplicationUpdateCommand.run(brew, ["upgrade", "--cask", "--greedy", token], environment: Self.brewEnvironment)
                        try ApplicationUpdatePolicy().validateCandidate(at: target.url, target: target)
                        finish(id, name: entry.item.name)
                        return
                    }
                }
                guard let target else { throw ApplicationUpdateFailure.refused("L’application installée est introuvable.") }
                var artifact = entry.item.artifact
                if artifact == nil, let token, ApplicationUpdatePolicy.validToken(token) {
                    let metadataURL = URL(string: "https://formulae.brew.sh/api/cask/\(token).json")!
                    let data = try await NativeApplicationUpdates.read(metadataURL, limit: 4_000_000)
                    let record = try JSONSerialization.jsonObject(with: data)
                    let catalog = try JSONSerialization.data(withJSONObject: [record])
                    let app = InstalledUpdateApplication(url: target.url, name: entry.item.name, bundleID: target.bundleID, version: target.version, appStore: false)
                    artifact = try HomebrewApplicationCatalog.updates(data: catalog, apps: [app]).first?.artifact
                }
                guard let artifact else { throw ApplicationUpdateFailure.refused("Aucune archive compatible n’est fournie pour cette application.") }
                activeTarget = target;states[id] = .downloading(nil)
                let prepared = try await ApplicationUpdateArchive.prepare(artifact: artifact, target: target, progress: { progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.activeID == id, case .downloading = self.states[id] else { return }
                        self.states[id] = .downloading(progress)
                    }
                }, verifying: {
                    Task { @MainActor [weak self] in
                        if self?.activeID == id { self?.states[id] = .verifying }
                    }
                })
                do {
                    try Task.checkCancellation()
                    if let package = prepared.package {
                        states[id] = .installing
                        guard NSWorkspace.shared.open(package) else { throw ApplicationUpdateFailure.refused("Impossible d’ouvrir l’installateur macOS.") }
                        pending[id] = prepared;states[id] = .waitingForInstaller;activeID = nil;task = nil
                    } else {
                        states[id] = .verifying;try Task.checkCancellation()
                        states[id] = .installing
                        try await ApplicationUpdateArchive.replace(prepared)
                        prepared.cleanup(); finish(id, name: entry.item.name)
                    }
                } catch { prepared.cleanup();throw error }
            } catch is CancellationError { states[id] = .cancelled;activeID = nil;task = nil }
            catch { states[id] = .failed(error.localizedDescription);activeID = nil;task = nil }
        }
    }

    func cancel() { if canCancel { task?.cancel() } }
    func hasPendingInstaller(_ id: String) -> Bool { pending[id] != nil }

    func verifyInstaller(_ entry: ApplicationUpdateEntry) {
        guard !isBusy, let prepared = pending[entry.id] else { return }
        do {
            try ApplicationUpdatePolicy().validateCandidate(at: prepared.target.url, target: prepared.target)
            guard try ApplicationUpdateArchive.teamID(at: prepared.target.url) == prepared.teamID else { throw ApplicationUpdateFailure.refused("La signature de l’application installée ne correspond pas.") }
            prepared.cleanup();pending[entry.id] = nil;finish(entry.id, name: entry.item.name)
        } catch { states[entry.id] = .failed("L’installation n’est pas encore confirmée. Terminez l’installateur et vérifiez à nouveau.") }
    }

    private static func quitNormally(_ url: URL) async throws {
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() }
        guard running.allSatisfy({ $0.terminate() }) else { throw ApplicationUpdateFailure.refused("L’application a refusé de quitter. Enregistrez vos documents et quittez-la avant de réessayer.") }
        for _ in 0..<300 {
            try Task.checkCancellation()
            if running.allSatisfy(\.isTerminated) { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ApplicationUpdateFailure.refused("L’application est toujours ouverte. Terminez son dialogue d’enregistrement puis réessayez.")
    }

    private static let brewEnvironment = ["HOMEBREW_NO_ANALYTICS":"1"]
    private static func isRunning(_ url: URL) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() }
    }
    private func sparkleBundle(_ url: URL) -> Bundle? {
        guard let bundle = Bundle(url: url), let raw = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feed = URL(string: raw), ApplicationUpdatePolicy.validDownloadURL(feed),
              let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, Data(base64Encoded: key)?.count == 32 else { return nil }
        return bundle
    }
    private func beginSparkle(bundle: Bundle, id: String) throws {
        // The external app is both the update target and relaunch target. MacCare never quits itself.
        let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: self)
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: self)
        externalUpdater = updater
        do { try updater.start() } catch { externalUpdater = nil;throw error }
        states[id] = .sparkle
        updater.checkForUpdates()
    }
    func standardUserDriverWillFinishUpdateSession() {
        if let id = activeID, installationIsConfirmed() { finish(id, name: activeName ?? "Application") }
    }
    private func installationIsConfirmed() -> Bool {
        guard let target = activeTarget else { return false }
        do { try ApplicationUpdatePolicy().validateCandidate(at: target.url, target: target);return true }
        catch { return false }
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard updater === externalUpdater else { return }
        if let id = activeID {
            if installationIsConfirmed() { finish(id, name: activeName ?? "Application") }
            else { states[id] = error.map { .failed($0.localizedDescription) } ?? .deferred;activeID = nil;task = nil }
        }
        // A subsequent update must not lose its controller to this deferred cleanup.
        Task { @MainActor [weak self] in
            if self?.externalUpdater === updater { self?.externalUpdater = nil }
        }
    }
    private func finish(_ id: String, name: String) {
        states[id] = .completed;lastCompletedID = id;lastResult = "\(name) a été mis à jour.";activeID = nil;activeTarget = nil;task = nil
    }
}
