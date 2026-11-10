import SwiftUI
import AppKit
import UserNotifications

struct AppUpdateSettingsView: View {
    @ObservedObject var updater: AppUpdater
    @AppStorage(AppUpdateNotifications.enabledKey) private var notificationsEnabled = AppUpdateNotifications.defaultEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Rechercher automatiquement les mises à jour", isOn: $updater.automaticallyChecksForUpdates)
                .disabled(!updater.isAvailable)
            Text("MacCare consulte les releases GitHub. Vous choisissez quand installer une nouvelle version.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Notifier lorsqu’une mise à jour est disponible", isOn: $notificationsEnabled)
                .disabled(!updater.isAvailable)
                .onChange(of: notificationsEnabled) { enabled in
                    if enabled { Task { await updater.requestUpdateNotificationPermission() } }
                    else { updater.clearUpdateNotification() }
                }
            Text("Une bannière par nouvelle version détectée lors des recherches automatiques. MacCare doit rester ouvert, même dans la barre des menus.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if notificationsEnabled, updater.isAvailable {
                if updater.notificationAuthorization == .notDetermined {
                    Button("Autoriser les notifications…") {
                        Task { await updater.requestUpdateNotificationPermission() }
                    }
                } else if updater.notificationAuthorization == .denied {
                    Text("Les notifications de MacCare sont désactivées dans macOS.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Ouvrir les réglages de notifications") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            if let error = updater.notificationError {
                Text(error).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                if let reason = updater.unavailableReason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let date = updater.lastCheckDate {
                    Text("Dernière recherche : \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Aucune recherche effectuée.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button("Rechercher les mises à jour…", action: updater.checkForUpdates)
                    .disabled(!updater.canCheckForUpdates)
            }
        }
        .task { await updater.refreshNotificationAuthorization() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await updater.refreshNotificationAuthorization() }
        }
    }
}
