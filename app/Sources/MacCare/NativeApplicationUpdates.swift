import Foundation

/// Local inventory only. The full public catalog is fetched without transmitting these values.
struct InstalledUpdateApplication: Sendable {
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    let appStore: Bool

    static func inventory() -> [Self] {
        AppCatalog.installedApps().compactMap { app in
            guard let bundle = Bundle(url: app.url), let id = bundle.bundleIdentifier,
                  let version = (bundle.object(forInfoDictionaryKey: "ArtCraftLauncherVersion") ??
                                 bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")) as? String else { return nil }
            return Self(url: app.url, name: app.name, bundleID: id, version: version,
                        appStore: FileManager.default.fileExists(atPath: app.url.appendingPathComponent("Contents/_MASReceipt/receipt").path))
        }
    }
}

/// Only dotted numeric marketing versions are comparable automatically. Build identifiers,
/// prereleases and `latest` require an explicit provider instead of guessing an ordering.
enum ApplicationReleaseVersion {
    static func normalized(_ value: String) -> String? {
        let value = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 6,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } && UInt64($0) != nil }) else { return nil }
        var numbers = parts.map { String(UInt64($0)!) }
        while numbers.count > 1 && numbers.last == "0" { numbers.removeLast() }
        return numbers.joined(separator: ".")
    }

    static func isNewer(_ available: String, than installed: String) -> Bool {
        guard let available = normalized(available), let installed = normalized(installed) else { return false }
        return available.compare(installed, options: .numeric) == .orderedDescending
    }
}

enum NativeApplicationUpdates {
    static let key = "catalog"
    static let catalogURL = URL(string: "https://formulae.brew.sh/api/cask.json")!

    static func read(_ url: URL, session: URLSession = .shared, limit: Int = 32_000_000) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("MacCare-Update-Check", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https", data.count <= limit else { throw URLError(.badServerResponse) }
        return data
    }

    static func check(apps: [InstalledUpdateApplication]? = nil,
                      fetch: (URL, Int) async throws -> Data = { try await read($0, limit: $1) }) async -> (String, UpdateSource.State, [OutdatedItem]) {
        let installed = (apps ?? InstalledUpdateApplication.inventory()).filter { !$0.appStore }
        guard !installed.isEmpty else { return (key, .notInstalled, []) }
        var items: [OutdatedItem] = []
        var failures: [String] = []
        do {
            let data = try await fetch(catalogURL, 32_000_000)
            items = try HomebrewApplicationCatalog.updates(data: data, apps: installed)
        } catch { failures.append("Catalogue Homebrew indisponible. Réessayez la vérification.") }
        // Known official sources take precedence over the community catalog.
        for source in OfficialGitHubApplication.catalog {
            let matches = installed.filter { $0.bundleID == source.bundleID }
            guard !matches.isEmpty else { continue }
            items.removeAll { item in matches.contains { $0.url == item.applicationURL } }
            do {
                let data = try await fetch(source.apiURL, 2_000_000)
                items += try source.updates(data: data, apps: matches)
            } catch { failures.append("\(source.name) : versions officielles indisponibles. Réessayez la vérification.") }
        }
        return (key, failures.isEmpty ? .ok : .error(failures.joined(separator: " ")), items)
    }
}
