import SwiftUI

/// Rappel global qui remet le panneau Sparkle et son changelog au premier plan.
struct AppUpdateAvailabilityButton: View {
    @ObservedObject var updater: AppUpdater
    @State private var hovered = false

    var body: some View {
        if let version = updater.availableVersion {
            Button(action: updater.checkForUpdates) {
                Label {
                    Text("Mise à jour disponible")
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                        .accessibilityHidden(true)
                }
                .labelStyle(.titleAndIcon)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .background(hovered ? Theme.updateNotice.shade(-0.05) : Theme.updateNotice, in: Capsule())
                .foregroundStyle(Theme.updateNoticeInk)
                .frame(minHeight: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .onHover { hovered = $0 }
            .disabled(!updater.canCheckForUpdates)
            .opacity(updater.canCheckForUpdates ? 1 : 0.65)
            .accessibilityLabel("Mise à jour de MacCare disponible")
            .accessibilityValue("Version \(version)")
            .accessibilityHint("Ouvrir les nouveautés et les options de mise à jour")
            .help("MacCare \(version) est disponible. Afficher les nouveautés et les options de mise à jour.")
        }
    }
}
