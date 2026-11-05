import AppKit
import SwiftUI

struct CPUAlertView: View {
    @ObservedObject var model: MemoryAlertModel
    let fraction: Double
    let snooze: (Int) -> Void
    let openActivity: () -> Void
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 14
    @State private var feedback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("CPU fortement sollicité").font(.system(size: titleSize, weight: .bold)).accessibilityAddTraits(.isHeader)
                Text("Le processeur reste très sollicité depuis deux minutes. Consultez l’activité ou fermez une application dont vous n’avez plus besoin.")
                    .font(.system(size: bodySize)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Charge du Mac : \(Int(fraction * 100)) %")
                    .font(.system(size: bodySize, weight: .semibold)).monospacedDigit().padding(.top, 12)
                ForEach(model.candidates) { candidate in
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: candidate.application.bundlePath))
                            .resizable().frame(width: 32, height: 32).accessibilityHidden(true)
                        Text(candidate.name).lineLimit(1).truncationMode(.tail).help(candidate.name)
                        Spacer(minLength: 0)
                        Text("\(Int(candidate.process.cpuPercent ?? 0)) %").monospacedDigit().fixedSize()
                            .help("Pourcentage du processus principal : 100 % correspond à un cœur.")
                        Button(model.pending.contains(candidate.id) ? "Demandé" : "Quitter") { model.quit(candidate) }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .disabled(model.pending.contains(candidate.id))
                            .accessibilityLabel("Quitter \(candidate.name)")
                    }.font(.system(size: bodySize, weight: .semibold)).padding(.top, 8)
                }
            }.padding(24)
            Divider()
            HStack {
                Menu("Ignorer") {
                    Button("Pendant une journée") { snooze(1) }
                    Button("Pendant une semaine") { snooze(7) }
                }.fixedSize()
                Spacer(minLength: 12)
                Button("Voir l’activité", action: openActivity).buttonStyle(StorageAlertPrimaryButtonStyle())
            }.padding(20)
        }
        .frame(width: 340)
        .onReceive(model.$message) { feedback = $0 != nil }
        .alert("Fermeture de l’application", isPresented: $feedback) {
            Button("Fermer", role: .cancel) { model.clearMessage() }
        } message: { Text(model.message ?? "") }
    }
}
