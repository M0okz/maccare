import Foundation

/// L’option autorise l’étape lors d’une action confirmée ; elle ne planifie aucune suppression.
enum PerformancePreferences {
    static let localSnapshotsKey = "performance.includeLocalTimeMachineSnapshots"
    static let includeLocalSnapshotsDefault = true
    static func includeLocalSnapshots(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: localSnapshotsKey) as? Bool ?? includeLocalSnapshotsDefault
    }
    static func allowsLocalSnapshots(confirmed: Bool, defaults: UserDefaults = .standard) -> Bool {
        confirmed && includeLocalSnapshots(in: defaults)
    }
}
