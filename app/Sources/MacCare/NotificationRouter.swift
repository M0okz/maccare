import Foundation
import UserNotifications

/// Route les clics vers le parcours concerné, avec un seul délégué de notifications.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: (() -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        if identifier != AppUpdateNotifications.identifier || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in self.openNotification(identifier: identifier) }
        }
        completionHandler()
    }

    @MainActor func openNotification(identifier: String) {
        if identifier == AppUpdateNotifications.identifier {
            NotificationCenter.default.post(name: .appUpdateNotificationSelected, object: nil)
        } else {
            onOpen?()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}

