import AppKit
import SwiftUI

struct MemoryAlertView: View {
    @ObservedObject var model: MemoryAlertModel
    let snooze: (Int) -> Void
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 14
    @State private var confirming = false
    @State private var showingFeedback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Consommation de mémoire élevée")
                    .font(.system(size: titleSize, weight: .bold)).accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Vous n’avez plus beaucoup de mémoire, et votre Mac peut devenir beaucoup plus lent. Envisagez de fermer des applications.")
                    .font(.system(size: bodySize)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 16) {
                    ForEach(model.candidates) { candidate in
                        HStack(spacing: 12) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: candidate.application.bundlePath))
                                .resizable().frame(width: 32, height: 32).accessibilityHidden(true)
                            Text(candidate.name).lineLimit(1).truncationMode(.tail).help(candidate.name)
                            Spacer(minLength: 0)
                            Text(candidate.memoryText).monospacedDigit().fixedSize().foregroundStyle(.red)
                                .help("Empreinte physique du processus principal, mémoire compressée comprise.")
                            Button(model.pending.contains(candidate.id) ? "Demandé" : "Quitter") { model.quit(candidate) }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                                .disabled(model.pending.contains(candidate.id))
                                .accessibilityLabel("Quitter \(candidate.name)")
                                .help("Demander la fermeture de \(candidate.name), en proposant d’enregistrer les documents si l’application le permet.")
                        }.font(.system(size: bodySize, weight: .semibold))
                    }
                }.padding(.top, 20)
            }.padding(24)
            Divider()
            HStack {
                Menu("Ignorer") {
                    Button("Pendant une journée") { snooze(1) }
                    Button("Pendant une semaine") { snooze(7) }
                }.fixedSize()
                Spacer(minLength: 12)
                Button("Tout forcer à quitter") { confirming = true }
                    .buttonStyle(StorageAlertPrimaryButtonStyle())
                    .disabled(!model.canForceQuit)
                    .alert("Forcer la fermeture des applications affichées ?", isPresented: $confirming) {
                        Button("Forcer à quitter", role: .destructive) { model.forceQuitDisplayed() }
                        Button("Annuler", role: .cancel) { }
                    } message: {
                        Text("Applications concernées : \(model.candidates.map(\.name).joined(separator: ", ")). L’arrêt est immédiat. Les modifications non enregistrées peuvent être perdues. Aucune autre application ne sera fermée.")
                    }
            }.padding(20)
        }
        .frame(width: 340)
        .onReceive(model.$message) { message in showingFeedback = message != nil }
        .alert("Fermeture des applications", isPresented: $showingFeedback) {
            Button("Fermer", role: .cancel) { model.clearMessage() }
        } message: { Text(model.message ?? "") }
    }
}
