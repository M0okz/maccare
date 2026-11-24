import AppKit
import SwiftUI

struct HomeProcessDetails: View {
    @ObservedObject var session: HomeProcessDetailSession
    @ObservedObject var controller: TrayProcessController
    let presentation: HomeProcessPresentation
    @State private var confirmation: StopRequest?
    @AccessibilityFocusState private var titleFocused: Bool

    private var opened: HomeProcessGroup { session.opened }
    private var inspection: HomeProcessInspection? { session.selection?.inspection }

    private struct StopRequest: Identifiable {
        let process: TrayProcess
        let force: Bool
        var id: TrayProcess.Identity { process.id }
    }

    private var live: HomeProcessGroup? {
        guard let group = session.group else { return nil }
        let initial = Set(opened.members.map(\.id))
        return group.members.contains { initial.contains($0.id) } ? group : nil
    }
    private var inspected: TrayProcess? {
        guard let live else { return nil }
        let target = session.selection?.id
        return live.members.first { $0.id == target }
    }

    var body: some View {
        let current = live ?? opened
        VStack(alignment: .leading, spacing: 20) {
            header(current)
            HStack(spacing: 16) {
                metric("CPU", current.cpuLabel)
                metric("Mémoire", HomeProcessMetric.memory(current.memory))
                metric("Énergie", current.energyLabel).help(ProcessEnergyScore.help)
            }
            if live == nil {
                Text("Le processus s’est terminé.").foregroundStyle(Theme.warn)
            } else {
                ViewThatFits(in: .vertical) {
                    details(current)
                    ScrollView { details(current) }
                }
                .frame(maxHeight: 372)
                .fixedSize(horizontal: false, vertical: true)
            }
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
                        Button("Quitter") { confirmation = StopRequest(process: process, force: false) }
                        Button("Forcer à quitter", role: .destructive) { confirmation = StopRequest(process: process, force: true) }
                    }.disabled(!process.canQuit || controller.pending.contains(process.id))
                }
            }.buttonStyle(.actionPill).controlSize(.small)
        }
        .padding(22)
        .frame(width: 594, alignment: .topLeading)
        .foregroundStyle(Theme.fg)
        .background(LinearGradient(colors: [Theme.windowTop, Theme.surface, Theme.window],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .onAppear { titleFocused = true }
        .alert(confirmation?.force == true ? "Forcer l’arrêt de ce processus ?" : "Quitter ce processus ?",
               isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), presenting: confirmation) { request in
            Button("Annuler", role: .cancel) {}
            Button(request.force ? "Forcer à quitter" : "Quitter", role: .destructive) { controller.quit(request.process, force: request.force) }
        } message: { request in
            Text("\(request.process.name) · PID \(request.process.id.pid)" + (request.force ? "\nLes modifications non enregistrées peuvent être perdues." : ""))
        }
    }

    private func details(_ current: HomeProcessGroup) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let process = inspected {
                if current.members.count > 1 {
                    Text("\(process.name) · PID \(String(process.id.pid))")
                        .font(.headline).accessibilityAddTraits(.isHeader)
                }
                processFields(process)
            } else {
                Text("Le processus sélectionné s’est terminé.").foregroundStyle(Theme.muted)
            }
            if current.members.count > 1 || inspected == nil { processMembers(current) }
        }
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func summary(_ group: HomeProcessGroup) -> String {
        "\(group.members.count) processus · CPU \(group.cpuLabel) · \(HomeProcessMetric.memory(group.memory)) · Énergie \(group.energyLabel)"
    }

    private func header(_ group: HomeProcessGroup) -> some View {
        HStack(spacing: 12) {
            Group {
                if let icon = controller.presentation(for: opened.representative).icon {
                    Image(nsImage: icon).renderingMode(.original).resizable()
                } else {
                    Image(systemName: "gearshape").font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.accentInk).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                }
            }
            .frame(width: 38, height: 38).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(opened.name).accessibilityFocused($titleFocused).font(AppFont.section).foregroundStyle(Theme.fg).lineLimit(2).accessibilityAddTraits(.isHeader)
                if group.members.count == 1, let member = group.members.first {
                    Text("PID \(String(member.id.pid))").contextMenu { copyPID(member) }
                } else {
                    Text("\(group.members.count) processus")
                }
            }
            .font(.callout).foregroundStyle(Theme.muted)
            Spacer()
            Button { presentation.close() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28).background(Theme.faint.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plainAction).keyboardShortcut(.cancelAction)
            .foregroundStyle(Theme.muted).accessibilityLabel("Fermer la fiche")
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 19, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func processFields(_ process: TrayProcess) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 12) {
            if inspection == nil && process.name == "WindowServer" {
                GridRow {
                    field("Type", "Processus système macOS").gridCellColumns(2)
                    field("Actif depuis", MacSystemSpecs.duration(Date().timeIntervalSince1970 - Double(process.id.startedSeconds)))
                }
            } else {
                GridRow {
                    field("Threads", inspection.map { String($0.threads) } ?? "—")
                    field("Fichiers ouverts", inspection?.files.map(String.init) ?? "—")
                    field("Actif depuis", MacSystemSpecs.duration(Date().timeIntervalSince1970 - Double(process.id.startedSeconds)))
                }
                GridRow {
                    field("Utilisateur", inspection?.user ?? "—")
                    field("Processus parent", inspection?.parent ?? "—").gridCellColumns(2)
                }
                if let service = inspection?.service {
                    GridRow {
                        field("Service launchd", service).gridCellColumns(inspection?.reason == nil ? 3 : 2)
                        if let reason = inspection?.reason { field("Motif launchd", reason) }
                    }
                }
            }
        }
        if let read = inspection?.diskRead, let written = inspection?.diskWritten {
            field("E/S disque", "Lecture \(HomeProcessMetric.memory(read)) · Écriture \(HomeProcessMetric.memory(written))")
        }
        if !process.executable.isEmpty { field("Exécutable", process.executable, path: true) }
        if let directory = inspection?.directory, !directory.isEmpty { field("Dossier de travail", directory, path: true) }
    }

    private func field(_ title: String, _ value: String, path: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
            Text(value).font(path ? .system(.callout, design: .monospaced) : .callout)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copyPID(_ member: TrayProcess) -> some View {
        Button("Copier le PID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(member.id.pid), forType: .string)
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
            }.font(.caption.weight(.semibold)).foregroundStyle(Theme.muted).padding(.horizontal, 6)
            ForEach(group.members) { member in
                Button { presentation.select(member, in: session) } label: {
                    HStack {
                        Text(member.name).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(member.id.pid)).frame(width: 60, alignment: .trailing)
                        Text(HomeProcessMetric.cpu(member.cpuPercent)).foregroundStyle(Color(nsColor: ProcessCPULevel(member.cpuPercent).accent ?? .labelColor))
                            .frame(width: 65, alignment: .trailing)
                        Text(HomeProcessMetric.memory(member.memory)).frame(width: 78, alignment: .trailing)
                    }
                    .font(.callout).monospacedDigit().padding(.horizontal, 6).padding(.vertical, 3)
                    .contentShape(Rectangle())
                }.buttonStyle(.plainAction)
                    .accessibilityAddTraits(selected == member.id ? .isSelected : [])
                    .contextMenu { copyPID(member) }
            }
        }
    }
}
