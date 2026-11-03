import Foundation

/// Lecture seule du canal stable officiel. Aucune archive n'est téléchargée ou exécutée.
struct NetNewsWireRelease: Hashable {
    let version: String
    let build: String
    let minimumSystem: String
    let date: String
    let bytes: UInt64
    let notes: String
}

final class NetNewsWireFeed: NSObject, XMLParserDelegate {
    private var releases: [NetNewsWireRelease] = []
    private var fields: [String: String] = [:]
    private var enclosure: [String: String] = [:]
    private var element = ""
    private var insideItem = false

    static func parse(_ data: Data) throws -> [NetNewsWireRelease] {
        let reader = NetNewsWireFeed()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse() else { throw parser.parserError ?? URLError(.cannotParseResponse) }
        return reader.releases
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        element = name
        if name == "item" { insideItem = true; fields = [:]; enclosure = [:] }
        if insideItem && name == "enclosure" { enclosure = attributes }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideItem { fields[element, default: ""] += string }
    }
    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        if insideItem { fields[element, default: ""] += String(decoding: data, as: UTF8.self) }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard name == "item" else { return }
        insideItem = false
        guard let version = enclosure["sparkle:shortVersionString"], let build = enclosure["sparkle:version"] else { return }
        // Affichage en texte uniquement : aucun HTML actif dans l'interface.
        let notes = (fields["description"] ?? "")
            .replacingOccurrences(of: "<li>", with: "\n• ")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        releases.append(.init(version: version, build: build,
                              minimumSystem: fields["sparkle:minimumSystemVersion", default: "0"].trimmingCharacters(in: .whitespacesAndNewlines),
                              date: fields["pubDate", default: ""].trimmingCharacters(in: .whitespacesAndNewlines),
                              bytes: UInt64(enclosure["length"] ?? "") ?? 0, notes: notes))
    }

    static func latest(_ releases: [NetNewsWireRelease], installedBuild: String, systemVersion: String) -> NetNewsWireRelease? {
        releases.filter {
            $0.build.compare(installedBuild, options: .numeric) == .orderedDescending &&
            $0.minimumSystem.compare(systemVersion, options: .numeric) != .orderedDescending
        }.max { $0.build.compare($1.build, options: .numeric) == .orderedAscending }
    }

    /// Le même flux fournit les nouveautés des versions intermédiaires, sans nouvelle requête.
    static func notesSince(_ releases: [NetNewsWireRelease], installedBuild: String, throughBuild: String, systemVersion: String) -> String {
        releases.filter {
            $0.build.compare(installedBuild, options: .numeric) == .orderedDescending &&
            $0.build.compare(throughBuild, options: .numeric) != .orderedDescending &&
            $0.minimumSystem.compare(systemVersion, options: .numeric) != .orderedDescending &&
            !$0.notes.isEmpty
        }.sorted { $0.build.compare($1.build, options: .numeric) == .orderedDescending }
            .map { "Version \($0.version)\n\($0.notes)" }.joined(separator: "\n\n")
    }

    static func check() async -> (String, UpdateSource.State, [OutdatedItem]) {
        let paths = ["/Applications/NetNewsWire.app", NSHomeDirectory() + "/Applications/NetNewsWire.app"]
        guard let bundle = paths.compactMap({ Bundle(path: $0) }).first,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return ("netnewswire", .notInstalled, [])
        }
        // Les éditions App Store suivent leur propre canal.
        guard !FileManager.default.fileExists(atPath: bundle.bundlePath + "/Contents/_MASReceipt/receipt") else {
            return ("netnewswire", .notInstalled, [])
        }
        do {
            let url = URL(string: "https://ranchero.com/downloads/netnewswire-release.xml")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 2_000_000 else { throw URLError(.badServerResponse) }
            let system = ProcessInfo.processInfo.operatingSystemVersion
            let systemVersion = "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
            let releases = try parse(data)
            guard !releases.isEmpty else { throw URLError(.cannotParseResponse) }
            guard let release = latest(releases, installedBuild: build, systemVersion: systemVersion) else { return ("netnewswire", .ok, []) }
            return ("netnewswire", .ok, [.init(name: "NetNewsWire", detail: "\(version) → \(release.version)",
                releaseNotes: notesSince(releases, installedBuild: build, throughBuild: release.build, systemVersion: systemVersion), publicationDate: release.date, downloadBytes: release.bytes,
                applicationURL: bundle.bundleURL)])
        } catch { return ("netnewswire", .error("Flux officiel indisponible : \(error.localizedDescription)"), []) }
    }
}
