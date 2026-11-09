import Foundation

/// Audited mappings to official stable release channels. No repository is inferred from an app name.
struct OfficialGitHubApplication {
    let name: String
    let bundleID: String
    let repository: String
    let macAssetSuffix: String

    static let catalog = [
        Self(name: "ArtCraft Launcher", bundleID: "ai.storyteller.artcraft-launcher",
             repository: "storytold/craft-launcher", macAssetSuffix: "-macos-universal.dmg")
    ]

    var apiURL: URL { URL(string: "https://api.github.com/repos/\(repository)/releases/latest")! }

    private func assetURL(tag: String, name: String) -> URL {
        var url = URL(string: "https://github.com/\(repository)/releases/download")!
        url.appendPathComponent(tag); url.appendPathComponent(name)
        return url
    }

    func updates(data: Data, apps: [InstalledUpdateApplication]) throws -> [OutdatedItem] {
        struct Release: Decodable {
            struct Asset: Decodable { let name: String; let size: UInt64; let digest: String? }
            let tag_name: String
            let draft: Bool
            let prerelease: Bool
            let body: String?
            let published_at: String?
            let assets: [Asset]
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease,
              ApplicationReleaseVersion.normalized(release.tag_name) != nil,
              let asset = release.assets.first(where: { $0.name.hasSuffix(macAssetSuffix) && !$0.name.contains("/") && !$0.name.contains("\\") }) else { return [] }
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        // Construct the destination from the reviewed repository, never a payload-provided URL.
        var url = URL(string: "https://github.com/\(repository)/releases/tag")!
        url.appendPathComponent(release.tag_name)
        return apps.filter {
            !$0.appStore && $0.bundleID == bundleID && ApplicationReleaseVersion.isNewer(version, than: $0.version)
        }.map { app in
            OutdatedItem(name: app.name, detail: "\(app.version) → \(version)",
                         releaseNotes: release.body, publicationDate: release.published_at,
                         downloadBytes: asset.size, applicationURL: app.url, downloadURL: url,
                         artifact: .init(url: assetURL(tag: release.tag_name, name: asset.name), sha256: asset.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }))
        }
    }
}
