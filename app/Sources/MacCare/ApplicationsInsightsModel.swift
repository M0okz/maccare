import Foundation
import Combine
import AppKit

@MainActor
final class ApplicationsInsightsModel: ObservableObject {
    @Published private(set) var snapshot = ApplicationInsightsSnapshot()
    @Published private(set) var isScanning = false
    @Published private(set) var isRemoving = false
    @Published var selectedInstallers = Set<String>()
    @Published private(set) var removalMessage: String?

    var installerBytes: UInt64 { snapshot.installers.reduce(0) { $0 + $1.size_bytes } }

    func scan(apps: [AppInfo]) {
        guard !isScanning, !isRemoving else { return }
        isScanning = true
        selectedInstallers = []
        removalMessage = nil
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        Task {
            let result = await Task.detached(priority: .utility) { ApplicationInsightsReader.scan(apps: apps, running: running) }.value
            snapshot = result
            isScanning = false
        }
    }

    func trashSelectedInstallers() {
        let selected = snapshot.installers.filter { selectedInstallers.contains($0.id) }
        guard !isScanning, !isRemoving, !selected.isEmpty, let rule = snapshot.installerRule else { return }
        isRemoving = true
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads").path
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<RemovalReport, Error> in
                Result { try Remover.remove(selected, scopeRoot: root, direct: false, rule: rule) }
            }.value
            switch result {
            case .success(let report):
                snapshot.installers.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
                selectedInstallers = selectedInstallers.intersection(Set(snapshot.installers.map(\.id)))
                removalMessage = "\(report.removed) mis à la Corbeille · \(report.refused.count + report.failed.count) non retirés"
            case .failure(let error): removalMessage = error.localizedDescription
            }
            isRemoving = false
        }
    }
}
