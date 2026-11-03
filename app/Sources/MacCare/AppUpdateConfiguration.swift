import Foundation

/// Configuration publique intégrée au paquet signé ; aucune identité GitHub n’est nécessaire dans l’app.
struct AppUpdateConfiguration {
    let feedURL: URL
    let publicKey: Data

    init?(info: [String: Any]) {
        guard let feed = info["SUFeedURL"] as? String,
              let components = URLComponents(string: feed), components.scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let url = components.url,
              let encodedKey = info["SUPublicEDKey"] as? String,
              let key = Data(base64Encoded: encodedKey), key.count == 32 else { return nil }
        feedURL = url
        publicKey = key
    }
}
