import Foundation
import UserNotifications

/// One local banner per release; the existing notification router retains ownership of the delegate.
@MainActor
final class AppUpdateNotifications {
    nonisolated static let identifier = "maccare.app-update"
    nonisolated static let enabledKey = "appUpdateNotificationsEnabled"
    nonisolated static let lastBuildKey = "appUpdateNotificationLastBuild"
    static let defaultEnabled = true

    typealias Authorization = @MainActor () async -> UNAuthorizationStatus
    typealias Delivery = @MainActor (UNNotificationRequest) async throws -> Void
    private let defaults: UserDefaults
    private let authorization: Authorization
    private let deliver: Delivery
    private let remove: () -> Void
    private var pendingBuild: String?
    private var generation = 0

    init(defaults: UserDefaults = .standard,
         authorization: @escaping Authorization = { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus },
         deliver: @escaping Delivery = { try await UNUserNotificationCenter.current().add($0) },
         remove: @escaping () -> Void = {
             UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
             UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
         }) {
        self.defaults = defaults
        self.authorization = authorization
        self.deliver = deliver
        self.remove = remove
    }

    var isEnabled: Bool { defaults.object(forKey: Self.enabledKey) as? Bool ?? Self.defaultEnabled }

    func authorizationStatus() async -> UNAuthorizationStatus { await authorization() }

    /// Permission is checked here, never requested by a background update check.
    @discardableResult
    func announce(version: String, build: String) async -> Bool {
        guard isEnabled, !version.isEmpty, !build.isEmpty,
              defaults.string(forKey: Self.lastBuildKey) != build, pendingBuild == nil else { return false }
        generation += 1
        let ticket = generation
        pendingBuild = build
        // Keep one delivery in flight until it finishes, including after clear().
        // A late completion can then safely remove its banner without clearing a newer one.
        defer { pendingBuild = nil }
        let status = await authorization()
        guard generation == ticket, isEnabled, !Task.isCancelled,
              status == .authorized || status == .provisional else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Mise à jour de MacCare disponible"
        content.body = "MacCare \(version) est disponible. Affichez les nouveautés et choisissez quand l’installer."
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: nil)
        do { try await deliver(request) } catch { return false }
        guard generation == ticket else { remove(); return false }
        guard isEnabled else { remove(); return false }
        defaults.set(build, forKey: Self.lastBuildKey)
        return true
    }

    /// Remove a reminder after user attention, dismissal, or disabling notifications.
    func clear() {
        generation += 1
        remove()
    }
}

extension Notification.Name {
    static let appUpdateNotificationSelected = Notification.Name("MacCare.AppUpdateNotificationSelected")
}
