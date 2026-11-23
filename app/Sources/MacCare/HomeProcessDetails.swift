import AppKit
import SwiftUI

struct HomeProcessDetails: View {
    let opened: HomeProcessGroup
    let matchedPID: TrayProcess.Identity?
    let group: HomeProcessGroup?
    @ObservedObject var controller: TrayProcessController
    @Environment(\.dismiss) private var dismiss
    @State private var inspectedID: TrayProcess.Identity?
    @State private var inspection: HomeProcessInspection?
    @State private var confirmation: StopRequest?

    private struct StopRequest: Identifiable {
        let process: TrayProcess
        let force: Bool
        var id: TrayProcess.Identity { process.id }
    }

    private var live: HomeProcessGroup? {
        guard let group else { return nil }
        let initial = Set(opened.members.map(\.id))
        return group.members.contains { initial.contains($0.id) } ? group : nil
    }
    private var inspected: TrayProcess? {
        guard let live else { return nil }
        let target = inspectedID ?? matchedPID ?? opened.primary?.id ?? opened.members[0].id
        return live.members.first { $0.id == target }
    }

    var body: some View {
        let current = live ?? opened
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let icon = controller.presentation(for: opened.primary ?? opened.members[0]).icon {
                    Image(nsImage: icon).renderingMode(.original).resizable().frame(width: 32, height: 32)
                }
                Text(opened.name).font(.title2.bold()).lineLimit(2).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Fermer la fiche")
            }
            Text(summary(current)).font(.callout).foregroundStyle(.secondary)
            if live == nil {
                Text("Le processus s’est terminé.").foregroundStyle(Theme.warn)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let process = inspected {
                            Text("\(process.name) · PID \(String(process.id.pid))").font(.headline)
                            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                                GridRow {
                                    field("Threads", inspection.map { String($0.threads) } ?? "—")
                                    field("Fichiers ouverts", inspection?.files.map(String.init) ?? "—")
                                    field("Actif depuis", MacSystemSpecs.duration(Date().timeIntervalSince1970 - Double(process.id.startedSeconds)))
                                }
                                GridRow {
                                    field("Utilisateur", inspection?.user ?? "—")
                                    field("Processus parent", inspection?.parent ?? "—").gridCellColumns(2)
                                }
                            }
                            if let service = inspection?.service {
                                field("Service launchd", service)
                                if let reason = inspection?.reason { field("Motif launchd", reason) }
                            }
                            if let read = inspection?.diskRead, let written = inspection?.diskWritten {
                                field("E/S disque", "Lecture \(HomeProcessMetric.memory(read)) · Écriture \(HomeProcessMetric.memory(written))")
                            }
                            if !process.executable.isEmpty { field("Exécutable", process.executable) }
                            if let directory = inspection?.directory, !directory.isEmpty { field("Dossier de travail", directory) }
                        } else {
                            Text("Le processus sélectionné s’est terminé.").foregroundStyle(.secondary)
                        }
                        Divider()
                        processMembers(current)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 6)
                }
            }
            Divider()
            HStack(spacing: 8) {
                Button("Copier le résumé") {
                    let paste = NSPasteboard.general
                    paste.clearContents()
                    paste.setString(([current.name, summary(current)] + current.members.map {
                        "\($0.name) · PID \($0.id.pid) · \(HomeProcessMetric.cpu($0.cpuPercent)) CPU · \(HomeProcessMetric.memory($0.memory))"
                    }).joined(separator: "\n"), forType: .string)
                }
                if let url = opened.application ?? inspected.flatMap({ $0.executable.isEmpty ? nil : URL(fileURLWithPath: $0.executable) }) {
                    Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                Spacer()
                if let process = inspected {
                    Group {
                        Button("Quitter…") { confirmation = StopRequest(process: process, force: false) }
                        Button("Forcer à quitter…", role: .destructive) { confirmation = StopRequest(process: process, force: true) }
                    }.disabled(!process.canQuit || controller.pending.contains(process.id))
                }
            }.controlSize(.regular).font(.system(size: 12))
        }
        .padding(22).frame(width: 602, height: 598, alignment: .topLeading)
        .task(id: inspected?.id) {
            inspection = nil
            guard let process = inspected else { return }
            let snapshot = await Task.detached(priority: .utility) { HomeProcessInspection.read(process) }.value
            if !Task.isCancelled { inspection = snapshot }
        }
        .alert(confirmation?.force == true ? "Forcer l’arrêt de ce processus ?" : "Quitter ce processus ?",
               isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), presenting: confirmation) { request in
            Button("Annuler", role: .cancel) {}
            Button(request.force ? "Forcer à quitter" : "Quitter", role: .destructive) { controller.quit(request.process, force: request.force) }
        } message: { request in
            Text("\(request.process.name) · PID \(request.process.id.pid)" + (request.force ? "\nLes modifications non enregistrées peuvent être perdues." : ""))
        }
    }

    private func summary(_ group: HomeProcessGroup) -> String {
        "\(group.members.count) processus · CPU \(group.cpuLabel) · \(HomeProcessMetric.memory(group.memory)) · \(group.powerLabel)"
    }

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).textSelection(.enabled)
        }
    }

    private func processMembers(_ group: HomeProcessGroup) -> some View {
        let selected = inspected?.id
        return VStack(spacing: 2) {
            HStack {
                Text("Processus").frame(maxWidth: .infinity, alignment: .leading)
                Text("PID").frame(width: 60, alignment: .trailing)
                Text("CPU").frame(width: 65, alignment: .trailing)
                Text("Mémoire").frame(width: 78, alignment: .trailing)
            }.font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 6)
            ForEach(group.members) { member in
                Button { inspectedID = member.id } label: {
                    HStack {
                        Text(member.name).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(member.id.pid)).frame(width: 60, alignment: .trailing)
                        Text(HomeProcessMetric.cpu(member.cpuPercent)).foregroundStyle((member.cpuPercent ?? 0) > 40 ? Theme.warn : .primary)
                            .frame(width: 65, alignment: .trailing)
                        Text(HomeProcessMetric.memory(member.memory)).frame(width: 78, alignment: .trailing)
                    }
                    .font(.callout).monospacedDigit().padding(.horizontal, 6).padding(.vertical, 3)
                    .background(selected == member.id ? Theme.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 4))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .contextMenu {
                        Button("Copier le PID") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(String(member.id.pid), forType: .string)
                        }
                    }
            }
        }
    }
}
