import Foundation

/// Le rôle du paquet est fixé avant signature, indépendamment de l’optimisation Swift.
enum AppBuildIdentity {
    static let isDevelopment = Bundle.main.object(forInfoDictionaryKey: "MacCareDevelopmentBuild") as? Bool ?? true
    static let name = isDevelopment ? "MacCare Dev" : "MacCare"
}
