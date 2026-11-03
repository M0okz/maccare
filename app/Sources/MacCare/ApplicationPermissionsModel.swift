import AppKit
import Foundation

@MainActor
final class ApplicationPermissionsModel: ObservableObject {
    @Published private(set) var snapshot = ApplicationPermissionSnapshot()
    @Published private(set) var busy = false
    @Published private(set) var hasScanned = false
    @Published private(set) var message: String?
    @Published var selection: Set<String> = []
    private let inspect: @Sendable () -> ApplicationPermissionSnapshot
    init(inspect: @escaping @Sendable () -> ApplicationPermissionSnapshot = { ApplicationPermissionStore.scan() }) { self.inspect = inspect }
    var chosen: [ApplicationPermission] { snapshot.entries.filter { selection.contains($0.id) && $0.canReset } }

    func scan() {
        guard !busy else { return }
        busy = true; selection = []
        let inspect = inspect
        Task {
            snapshot = await Task.detached(priority: .userInitiated) { inspect() }.value
            busy = false; hasScanned = true
        }
    }

    func resetSelected() {
        let entries = chosen
        guard !busy && !entries.isEmpty else { return }
        busy = true; selection = []
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                var succeeded = 0, errors: [String] = []
                for entry in entries {
                    do { try ApplicationPermissionStore.reset(entry); succeeded += 1 }
                    catch { errors.append(error.localizedDescription) }
                }
                return (succeeded, errors)
            }.value
            message = "\(result.0) autorisation(s) réinitialisée(s)." + (result.1.isEmpty ? " Les applications devront redemander votre accord." : " " + result.1.joined(separator: " "))
            busy = false; scan()
        }
    }

    func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
    func name(for entry: ApplicationPermission) -> String {
        if entry.clientType == 1 { return URL(fileURLWithPath: entry.client).lastPathComponent }
        return AppNames.name(for: entry.client)
    }
}
