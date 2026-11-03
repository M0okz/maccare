import Foundation
import AppKit

/// Un reste d'application supprimée, avec de quoi l'identifier à l'écran.
struct LeftoverItem: Identifiable, Hashable {
    let item: ScanItem
    /// Nature du reste : « Données d'app », « Préférences », « Agent orphelin »…
    let kind: String
    /// Identifiant de l'app disparue (ou libellé de l'agent).
    let owner: String
    var id: String { item.id }
}

/// Repère des restes d'applications désinstallées dans `~/Library`.
///
/// Heuristique volontairement prudente, car une erreur toucherait les données d'une app encore
/// utilisée. Un élément n'est proposé que si :
///  - son nom est un identifiant de bundle (`com.éditeur.produit`) ;
///  - l'éditeur (les deux premiers composants) n'a **aucune** app installée : on ignore donc les
///    assistants, mises à jour et données partagées d'un éditeur dont une autre app est présente ;
///  - aucun mot de son nom (« immich », « codexbar »…) ne figure dans une app installée, ce qui
///    écarte les données d'une app dont l'identifiant d'éditeur diffère de celui de son conteneur ;
///  - ce n'est ni un composant système ni un outil de développement connu.
/// « Installée » couvre /Applications et ses sous-dossiers, l'index Spotlight (autres volumes,
/// ~/Applications…), les apps en cours d'exécution et MacCare lui-même.
/// S'y ajoutent les agents de lancement dont le programme n'existe plus.
/// Rien n'est jamais présélectionné ; le moteur re-valide tout avant la corbeille.
enum LeftoverScanner {
    private struct Location {
        let dir: String
        let kind: String
        let suffixes: [String]
    }

    /// Emplacements de `~/Library` où un identifiant de bundle sert de nom. Les caches et logs
    /// n'y figurent pas : ils sont déjà proposés par les règles de nettoyage.
    private static let locations: [Location] = [
        Location(dir: "Application Support", kind: "Données d'app", suffixes: []),
        Location(dir: "Preferences", kind: "Préférences", suffixes: [".plist"]),
        Location(dir: "Containers", kind: "Conteneur", suffixes: []),
        Location(dir: "Group Containers", kind: "Conteneur partagé", suffixes: []),
        Location(dir: "Saved Application State", kind: "État de fenêtres", suffixes: [".savedState"]),
        Location(dir: "HTTPStorages", kind: "Stockage réseau", suffixes: [".binarycookies"]),
        Location(dir: "WebKit", kind: "Données web", suffixes: []),
    ]

    /// Identifiants jamais proposés : composants système, frameworks partagés et outils de
    /// développement, pas des apps à nettoyer. Testé sur l'identifiant en minuscules.
    private static let deniedPrefixes = [
        "com.apple.", "org.swift.", "org.sparkle-project.", "is.workflow.", "org.cups.", "org.freedesktop.",
    ]
    /// Les conteneurs d'Apple s'écrivent aussi « ÉQUIPE.groups.com.apple.xxx » : on cherche « .apple. ».
    private static let deniedFragments = [".apple."]

    /// Mots trop courants pour prouver qu'une app est installée.
    private static let genericTokens: Set<String> = [
        "helper", "helpers", "agent", "launcher", "updater", "share", "shared", "extension", "extensions",
        "macos", "desktop", "client", "server", "service", "services", "plugin", "widget", "tools",
        "lite", "free", "group", "groups", "preferences", "settings", "support", "framework", "downloader",
    ]

    static func scan() -> [LeftoverItem] {
        let installed = installedApps()
        let library = (NSHomeDirectory() as NSString).appendingPathComponent("Library")
        let fm = FileManager.default

        var candidates: [(path: String, kind: String, owner: String)] = []

        for location in locations {
            let dir = (library as NSString).appendingPathComponent(location.dir)
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names {
                guard let id = bundleID(from: name, in: location) else { continue }
                let lower = id.lowercased()
                if deniedPrefixes.contains(where: { lower.hasPrefix($0) }) { continue }
                if deniedFragments.contains(where: { lower.contains($0) }) { continue }
                guard let vendor = vendor(of: lower), !installed.vendors.contains(vendor) else { continue }
                // Un mot du nom retrouvé dans une app installée : on suppose qu'elle est toujours là.
                if !Set(tokens(of: lower)).isDisjoint(with: installed.tokens) { continue }
                candidates.append(((dir as NSString).appendingPathComponent(name), location.kind, id))
            }
        }

        candidates += orphanLaunchAgents(in: library)

        guard !candidates.isEmpty,
              let items = try? Engine.inspectPaths(candidates.map(\.path), category: "leftover") else { return [] }

        let meta = Dictionary(candidates.map { ($0.path, ($0.kind, $0.owner)) }, uniquingKeysWith: { first, _ in first })
        return items
            .filter { $0.size_bytes > 0 }
            .compactMap { item in
                meta[item.path].map { LeftoverItem(item: item, kind: $0.0, owner: $0.1) }
            }
            .sorted { $0.item.size_bytes > $1.item.size_bytes }
    }

    // MARK: Agents de lancement orphelins

    /// Agents de `~/Library/LaunchAgents` dont le programme (chemin absolu) n'existe plus.
    private static func orphanLaunchAgents(in library: String) -> [(path: String, kind: String, owner: String)] {
        let fm = FileManager.default
        let dir = (library as NSString).appendingPathComponent("LaunchAgents")
        var result: [(path: String, kind: String, owner: String)] = []
        for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where name.hasSuffix(".plist") {
            let path = (dir as NSString).appendingPathComponent(name)
            guard let data = fm.contents(atPath: path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
            else { continue }
            let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
            guard let program, program.hasPrefix("/"),
                  !program.hasPrefix("/Volumes/"),            // volume peut-être simplement non monté
                  !fm.fileExists(atPath: program) else { continue }
            // On ne conclut que si le dossier parent est lisible : sinon l'absence peut être un refus d'accès.
            let parent = (program as NSString).deletingLastPathComponent
            guard (try? fm.contentsOfDirectory(atPath: parent)) != nil else { continue }
            result.append((path, "Agent orphelin", (plist["Label"] as? String) ?? name))
        }
        return result
    }

    // MARK: Identifiants et éditeurs

    /// Extrait l'identifiant de bundle d'un nom d'entrée, ou nil si ce n'en est pas un.
    private static func bundleID(from name: String, in location: Location) -> String? {
        if name.hasPrefix(".") { return nil }
        var id = name
        var stripped = false
        for suffix in location.suffixes where id.hasSuffix(suffix) {
            id.removeLast(suffix.count)
            stripped = true
            break
        }
        if location.dir == "Preferences", !stripped { return nil }   // seuls les fichiers .plist

        if location.dir == "Group Containers" {
            // « group.com.x.y » ou « ABCDE12345.com.x.y » (préfixe d'équipe de 10 caractères).
            if id.hasPrefix("group.") {
                id.removeFirst("group.".count)
            } else if id.hasPrefix("groups.") {
                id.removeFirst("groups.".count)
            } else if let dot = id.firstIndex(of: "."), id[..<dot].count == 10,
                      id[..<dot].allSatisfy({ $0.isNumber || ($0.isLetter && $0.isUppercase) }) {
                id = String(id[id.index(after: dot)...])
                if id.hasPrefix("group.") { id.removeFirst("group.".count) }
                else if id.hasPrefix("groups.") { id.removeFirst("groups.".count) }
            }
        }
        return looksLikeBundleID(id) ? id : nil
    }

    /// Au moins trois composants, le premier étant un suffixe de domaine en minuscules (`com`, `org`…).
    private static func looksLikeBundleID(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, let tld = parts.first,
              (2...6).contains(tld.count), tld.allSatisfy({ $0.isLetter && $0.isLowercase }) else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }

    /// « com.google.Chrome.helper » → « com.google ».
    private static func vendor(of id: String) -> String? {
        let parts = id.split(separator: ".")
        return parts.count >= 2 ? "\(parts[0]).\(parts[1])" : nil
    }

    /// Mots significatifs d'un identifiant (4 caractères ou plus, hors mots trop courants).
    private static func tokens(of id: String) -> [String] {
        id.lowercased().split(separator: ".").map(String.init)
            .filter { $0.count >= 4 && !genericTokens.contains($0) }
    }

    /// Apps installées : éditeurs, et mots de leurs noms et identifiants.
    private struct Installed {
        var vendors = Set<String>()
        var tokens = Set<String>()
    }

    private static func installedApps() -> Installed {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var paths = Set<String>()

        // 1. Dossiers d'applications habituels, avec un niveau de sous-dossiers.
        func collect(_ dir: String, depth: Int) {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for name in names {
                let path = dir + "/" + name
                if name.hasSuffix(".app") {
                    paths.insert(path)
                } else if depth > 0 {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                        collect(path, depth: depth - 1)
                    }
                }
            }
        }
        for root in ["/Applications", "/Applications/Utilities", "/System/Applications",
                     "/System/Applications/Utilities", home + "/Applications"] {
            collect(root, depth: 1)
        }

        // 2. Index Spotlight : apps hors des dossiers habituels (autres volumes, ~/Downloads…).
        let spotlight = SystemTools.run("/usr/bin/mdfind", ["kMDItemContentType == \"com.apple.application-bundle\""])
        if spotlight.ok {
            for line in spotlight.stdout.split(separator: "\n") where line.hasSuffix(".app") {
                paths.insert(String(line))
            }
        }

        var result = Installed()
        func add(id: String?, name: String) {
            if let id {
                let lower = id.lowercased()
                if let v = vendor(of: lower) { result.vendors.insert(v) }
                result.tokens.formUnion(tokens(of: lower))
            }
            // Mots du nom d'affichage : « Alt Tab », « Visual Studio Code »…
            let words = name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            result.tokens.formUnion(words.filter { $0.count >= 4 && !genericTokens.contains($0) })
            let compact = name.lowercased().filter { $0.isLetter || $0.isNumber }
            if compact.count >= 4, !genericTokens.contains(compact) { result.tokens.insert(compact) }
        }

        for path in paths {
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            add(id: Bundle(path: path)?.bundleIdentifier, name: name)
        }

        // 3. Apps en cours d'exécution (même lancées depuis un dossier de build) et MacCare.
        for app in NSWorkspace.shared.runningApplications {
            add(id: app.bundleIdentifier, name: app.localizedName ?? "")
        }
        add(id: Bundle.main.bundleIdentifier, name: "MacCare")
        return result
    }
}
