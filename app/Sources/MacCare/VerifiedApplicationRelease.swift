import Foundation

/// Explicit exceptions for signed vendor releases whose marketing version omits
/// a patch number. A build alone never implies an arbitrary published version.
struct VerifiedApplicationRelease {
    let bundleID: String
    let marketingVersion: String
    let build: String
    let version: String
    let artifact: ApplicationUpdateArtifact

    static let catalog = [
        iStat(version: "7.50.2", build: "2394", sha256: "8c633ede51c431e0e9dcba864a2ac3499e9dc1c2ff5d849450b2b1e09c7d3d92"),
        iStat(version: "7.50.3", build: "2395", sha256: "e477dc76606a6181697652ead6f3ce977e716b878165ac1aa945cc470b9ce25d")
    ]

    private static func iStat(version: String, build: String, sha256: String) -> Self {
        Self(bundleID: "com.bjango.istatmenus", marketingVersion: "7.50", build: build, version: version,
             artifact: .init(url: URL(string: "https://cdn.istatmenus.app/files/istatmenus7/versions/iStatMenus\(version).zip")!, sha256: sha256))
    }

    static func matching(_ info: [String: Any]) -> Self? {
        catalog.first {
            info["CFBundleIdentifier"] as? String == $0.bundleID &&
            info["CFBundleShortVersionString"] as? String == $0.marketingVersion &&
            info["CFBundleVersion"] as? String == $0.build
        }
    }

    static func artifact(bundleID: String, version: String, url: URL) -> ApplicationUpdateArtifact? {
        catalog.first { $0.bundleID == bundleID && $0.version == version && $0.artifact.url == url }?.artifact
    }
}
