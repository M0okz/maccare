import Foundation
import SwiftUI
import AppKit

/// Un paquet/app obsolète détecté par un gestionnaire.
struct OutdatedItem: Identifiable, Hashable, Sendable {
    let name: String
    let detail: String
    var releaseNotes: String? = nil
    var publicationDate: String? = nil
    var downloadBytes: UInt64? = nil
    var applicationURL: URL? = nil
    var downloadURL: URL? = nil
    var catalogToken: String? = nil
    var artifact: ApplicationUpdateArtifact? = nil
    var storeID: UInt64? = nil
    var id: String { (applicationURL?.path ?? name) + detail }
}

/// Un gestionnaire de mises à jour et son état.
struct UpdateSource: Identifiable, Sendable {
    enum State: Equatable, Sendable { case notInstalled, checking, ok, error(String) }
    let key: String
    let title: String
    let command: String          // commande à exécuter soi-même pour mettre à jour
    var state: State = .checking
    var items: [OutdatedItem] = []
    var id: String { key }
    var isApplicationSource: Bool { ["cask", "mas", "netnewswire", NativeApplicationUpdates.key].contains(key) }
}

/// Vérifie les mises à jour en lecture seule via le catalogue public, les sources officielles,
/// Homebrew, mas embarqué et softwareupdate. Affiche un lien ou une commande, sans installation.
@MainActor
final class UpdatesModel: ObservableObject {
    @Published private(set) var sources: [UpdateSource] = []
    @Published private(set) var isChecking = false
    @Published private(set) var hasChecked = false
    @Published var copiedCommand: String?

    /// Nombre de mises à jour Homebrew connues localement (aperçu du tableau de bord), nil si inconnu.
    @Published private(set) var quickCount: Int?

    /// Total de la dernière vérification complète.
    var totalCount: Int { sources.reduce(0) { $0 + $1.items.count } }

    /// Aperçu **local** pour le tableau de bord : Homebrew seulement, sans réseau et sans mettre
    /// `brew` à jour (aucun effet de bord au lancement). La vérification complète reste à la demande.
    func quickCheck() {
        guard quickCount == nil else { return }
        Task.detached(priority: .utility) {
            guard let brew = SystemTools.locate("brew") else { return }
            let env = ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1"]
            var count = 0
            for cask in [false, true] {
                let args = ["outdated"] + (cask ? ["--cask"] : [])
                let out = SystemTools.run(brew, args, environment: env)
                if out.ok { count += out.stdout.split(separator: "\n").count }
            }
            let total = count
            await MainActor.run { self.quickCount = total }
        }
    }

    func check() { check(applicationsOnly: false) }

    /// Le bilan Applications ne mélange pas les apps avec macOS ou les outils en ligne de commande.
    func checkApplications() { check(applicationsOnly: true) }

    private func check(applicationsOnly: Bool) {
        guard !isChecking else { return }
        isChecking = true
        copiedCommand = nil
        sources = [
            UpdateSource(key: NativeApplicationUpdates.key, title: "Catalogue d’applications", command: ""),
            UpdateSource(key: "netnewswire", title: "NetNewsWire · Sparkle", command: ""),
            UpdateSource(key: "brew", title: "Homebrew", command: "brew upgrade"),
            UpdateSource(key: "cask", title: "Homebrew (apps)", command: "brew upgrade --cask"),
            UpdateSource(key: "mas", title: "App Store", command: ""),
            UpdateSource(key: "macos", title: "macOS", command: "softwareupdate -ia"),
        ].filter { !applicationsOnly || $0.isApplicationSource }
        let definitions = sources
        Task.detached(priority: .userInitiated) {
            let token = PowerAssertion.beginUserActivity("MacCare · mises à jour")
            defer { PowerAssertion.end(token) }
            let brew = SystemTools.locate("brew")
            await Self.checkConcurrently(sources: definitions, using: { key in
                await Self.checkSource(key, brew: brew)
            }, didUpdate: { self.sources = $0 })
            await MainActor.run {
                self.isChecking = false
                self.hasChecked = true
            }
        }
    }

    typealias CheckResult = (String, UpdateSource.State, [OutdatedItem])

    /// Each provider finishes independently. Keep raw results so duplicate suppression is
    /// recomputed from all evidence, regardless of the order in which providers finish.
    nonisolated static func checkConcurrently(
        sources: [UpdateSource],
        using check: @escaping @Sendable (String) async -> CheckResult,
        didUpdate: @MainActor ([UpdateSource]) -> Void
    ) async {
        await withTaskGroup(of: CheckResult.self) { group in
            for source in sources { group.addTask { await check(source.key) } }
            var rawSources = sources
            for await result in group {
                guard let index = rawSources.firstIndex(where: { $0.key == result.0 }) else { continue }
                rawSources[index].state = result.1
                rawSources[index].items = result.2
                await didUpdate(removingCatalogDuplicates(rawSources))
            }
        }
    }

    nonisolated private static func checkSource(_ key: String, brew: String?) async -> CheckResult {
        switch key {
        case NativeApplicationUpdates.key: return await NativeApplicationUpdates.check()
        case "netnewswire": return await NetNewsWireFeed.check()
        default:
            // Process.waitUntilExit is blocking: use a worker queue rather than occupy
            // a Swift cooperative executor thread while another provider needs to run.
            return await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let result: CheckResult
                    switch key {
                    case "brew": result = brewOutdated(brew, cask: false)
                    case "cask": result = brewOutdated(brew, cask: true)
                    case "mas": result = AppStoreUpdates.check()
                    default: result = macosOutdated()
                    }
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// A catalog match knows the actual bundle version; suppress the duplicate CLI receipt row.
    nonisolated static func removingCatalogDuplicates(_ sources: [UpdateSource]) -> [UpdateSource] {
        let tokens = Set(sources.filter { $0.key == NativeApplicationUpdates.key }.flatMap { $0.items.compactMap(\.catalogToken) })
        let urls = Set(sources.filter { $0.key == "netnewswire" }.flatMap { $0.items.compactMap(\.applicationURL) })
        return sources.map { source in
            var source = source
            if source.key == "cask" { source.items.removeAll { tokens.contains($0.name) } }
            if source.key == NativeApplicationUpdates.key { source.items.removeAll { $0.applicationURL.map(urls.contains) ?? false } }
            return source
        }
    }

    // MARK: Lecteurs (exécutés hors du main thread)

    nonisolated private static func brewOutdated(_ brew: String?, cask: Bool) -> (String, UpdateSource.State, [OutdatedItem]) {
        let key = cask ? "cask" : "brew"
        guard let brew else { return (key, .notInstalled, []) }
        var args = ["outdated", "--verbose"]
        if cask { args.append("--cask") }
        let out = SystemTools.run(brew, args, environment: ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1"])
        guard out.ok else { return (key, .error(out.stderr.isEmpty ? "échec de brew" : out.stderr), []) }
        let items = out.stdout.split(separator: "\n").map { line -> OutdatedItem in
            let s = String(line)
            if let sp = s.firstIndex(of: " ") {
                return OutdatedItem(name: String(s[..<sp]), detail: String(s[sp...]).trimmingCharacters(in: .whitespaces))
            }
            return OutdatedItem(name: s, detail: "")
        }
        return (key, .ok, items)
    }

    nonisolated private static func macosOutdated() -> (String, UpdateSource.State, [OutdatedItem]) {
        let out = SystemTools.run("/usr/sbin/softwareupdate", ["-l"])
        // softwareupdate écrit souvent sur stderr ; on scanne les deux.
        let text = out.stdout + "\n" + out.stderr
        if text.localizedCaseInsensitiveContains("No new software available") {
            return ("macos", .ok, [])
        }
        var items: [OutdatedItem] = []
        for line in text.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("* Label:") {
                items.append(OutdatedItem(name: s.replacingOccurrences(of: "* Label:", with: "").trimmingCharacters(in: .whitespaces), detail: ""))
            } else if s.hasPrefix("Title:") {
                if !items.isEmpty {
                    items[items.count - 1] = OutdatedItem(name: items[items.count - 1].name, detail: describeMacOSUpdate(s))
                }
            }
        }
        return ("macos", .ok, items)
    }

    /// Reformate la ligne « Title: …, Version: …, Size: …KiB, Action: restart » de `softwareupdate -l`
    /// en un résumé lisible : « Version 27.2 · 6,21 Go · redémarrage requis ».
    nonisolated private static func describeMacOSUpdate(_ line: String) -> String {
        var parts: [String] = []
        for field in line.split(separator: ",") {
            let f = field.trimmingCharacters(in: .whitespaces)
            if f.hasPrefix("Version:") {
                parts.append("Version " + f.dropFirst("Version:".count).trimmingCharacters(in: .whitespaces))
            } else if f.hasPrefix("Size:") {
                let raw = f.dropFirst("Size:".count).trimmingCharacters(in: .whitespaces)
                if raw.hasSuffix("KiB"), let kib = UInt64(raw.dropLast(3)) {
                    parts.append(humanSize(kib * 1024))
                }
            } else if f.hasPrefix("Action:") {
                if f.dropFirst("Action:".count).trimmingCharacters(in: .whitespaces) == "restart" {
                    parts.append("redémarrage requis")
                }
            }
        }
        return parts.joined(separator: " · ")
    }

    func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copiedCommand = command
    }
}
