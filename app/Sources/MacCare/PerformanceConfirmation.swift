import Foundation
import MacCareMaintenance

/// La feuille reçoit une sélection immuable dès sa première présentation.
struct PerformanceConfirmation: Identifiable {
    let id = UUID()
    let tasks: [PerformanceTask]
    let includeLocalSnapshots: Bool

    init(tasks: [PerformanceTask], includeLocalSnapshots: Bool = PerformancePreferences.includeLocalSnapshots()) {
        self.tasks = tasks
        self.includeLocalSnapshots = includeLocalSnapshots
    }
}
