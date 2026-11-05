import SwiftUI

struct TrayProcessList: View {
    @ObservedObject var controller: TrayProcessController
    let memory: Bool
    @State private var target: TrayProcess?
    @State private var force = false
    @State private var confirming = false

    private var ranked: [TrayProcess] {
        Array(controller.processes.sorted {
            let left = memory ? Double($0.memory) : ($0.cpuPercent ?? -1)
            let right = memory ? Double($1.memory) : ($1.cpuPercent ?? -1)
            return left == right ? $0.id.pid < $1.id.pid : left > right
        }.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Processus gourmands").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(memory ? "Mémoire" : "CPU").font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            if ranked.isEmpty {
                Text("Lecture des processus accessibles…").font(.caption).foregroundStyle(.white.opacity(0.75))
            }
            ForEach(ranked) { process in
                processRow(process)
            }
            Text("Les 6 plus gourmands parmi les processus accessibles.")
                .font(.caption2).foregroundStyle(.white.opacity(0.66))
            Text(memory ? "Empreinte physique par processus, mémoire compressée comprise." : "100 % correspond à un cœur utilisé. Un processus peut dépasser 100 %.")
                .font(.caption2).foregroundStyle(.white.opacity(0.66))
            if let message = controller.message {
                Text(message).font(.caption).foregroundStyle(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog(force ? "Forcer la fermeture ?" : "Quitter ce processus ?", isPresented: $confirming, titleVisibility: .visible) {
            if let target {
                Button(force ? "Forcer à quitter \(displayName(target))" : "Quitter \(displayName(target))", role: .destructive) {
                    controller.quit(target, force: force)
                }
            }
            Button("Annuler", role: .cancel) { target = nil }
        } message: {
            if let target {
                Text(force ? "\(displayName(target)) (PID \(target.id.pid)) sera arrêté immédiatement. Les modifications non enregistrées seront perdues." :
                        "Demander la fermeture de \(displayName(target)) (PID \(target.id.pid)). L’application peut vous demander d’enregistrer vos documents.")
            }
        }
    }

    private func processRow(_ process: TrayProcess) -> some View {
        HStack(spacing: 8) {
            if let icon = controller.presentation(for: process).icon {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22).accessibilityHidden(true)
            } else {
                Image(systemName: "app.dashed").frame(width: 22, height: 22).foregroundStyle(.white.opacity(0.65)).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(process)).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text("PID \(process.id.pid)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(memory ? humanSize(process.memory) : process.cpuPercent.map { String(format: "%.1f %%", $0) } ?? "—")
                .font(.system(size: 11, weight: .medium)).monospacedDigit().frame(minWidth: 65, alignment: .trailing)
            Menu {
                Button("Quitter") { select(process, force: false) }
                Button("Forcer à quitter…", role: .destructive) { select(process, force: true) }
            } label: {
                Text(controller.pending.contains(process.id) ? "En attente" : "Quitter")
                    .font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton).fixedSize()
            .disabled(!process.canQuit)
            .accessibilityLabel("Quitter \(displayName(process)), PID \(process.id.pid)")
            .help(process.canQuit ? "Demander ou forcer la fermeture" : "Processus système, protégé ou MacCare")
        }
        .padding(.vertical, 3)
    }

    private func select(_ process: TrayProcess, force: Bool) {
        target = process
        self.force = force
        confirming = true
    }

    private func displayName(_ process: TrayProcess) -> String {
        controller.presentation(for: process).name
    }
}
