import AppKit
import ServiceManagement
import SwiftUI

/// The login item choice and its status as macOS reports it. Never enabled without this control.
struct LoginLaunchToggle: View {
    @State private var status = LoginLaunch.status
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Ouvrir MacCare à la connexion", isOn: Binding(
                get: { status == .enabled || status == .requiresApproval },
                set: { on in
                    do { try LoginLaunch.set(on); failure = nil } catch { failure = error.localizedDescription }
                    status = LoginLaunch.status
                }
            )).disabled(status == .notFound)
            statusText
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = LoginLaunch.status
        }
    }

    @ViewBuilder private var statusText: some View {
        switch status {
        case .enabled:
            Text("Activée.").font(AppFont.secondary).foregroundStyle(.secondary)
        case .requiresApproval:
            HStack(spacing: 6) {
                Label("En attente de votre approbation dans les Réglages Système.", systemImage: "exclamationmark.circle")
                    .font(AppFont.secondary).foregroundStyle(.orange)
                Button("Ouvrir") { SMAppService.openSystemSettingsLoginItems() }.buttonStyle(LinkStyle()).font(AppFont.secondary)
            }
        case .notFound:
            Text("Indisponible depuis cet emplacement : placez MacCare dans le dossier Applications.")
                .font(AppFont.secondary).foregroundStyle(.orange)
        default:
            Text(failure.map { "Impossible : \($0)" } ?? "Désactivée.")
                .font(AppFont.secondary).foregroundStyle(failure == nil ? Color.secondary : Color.orange)
        }
    }
}
