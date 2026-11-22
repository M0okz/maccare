import AppKit
import SwiftUI

/// Le tableau et la carte Batterie utilisent le même relevé des processus accessibles.
struct HomeProcessTable: View {
    @ObservedObject var controller: TrayProcessController
    @State private var query = ""
    @State private var sort = [KeyPathComparator(\TrayProcess.memory, order: .reverse)]
    @State private var sortedRows: [TrayProcess] = []
    @State private var highCPUApps: [HomeCPUApplication] = []
    @State private var quitTarget: TrayProcess?

    private var rows: [TrayProcess] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return sortedRows }
        return sortedRows.filter {
            $0.name.localizedCaseInsensitiveContains(term) || String($0.id.pid).contains(term)
        }
    }

    private func updateOrder(_ processes: [TrayProcess]) {
        sortedRows = processes.sorted(using: sort + [KeyPathComparator(\TrayProcess.id.pid)])
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Processus").font(.headline).accessibilityAddTraits(.isHeader)
                Text(controller.processes.count.formatted()).font(AppFont.caption).monospacedDigit()
                    .foregroundStyle(Theme.muted).accessibilityLabel("\(controller.processes.count) processus accessibles")
                ForEach(highCPUApps) { app in
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").font(.caption2)
                        Text(app.name).lineLimit(1).truncationMode(.tail)
                        Text(app.percentLabel).monospacedDigit().fixedSize()
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.warn)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.warn.opacity(0.10), in: Capsule())
                    .help("\(app.name) · \(app.percentLabel) CPU, processus auxiliaires compris.")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(app.name), charge CPU élevée, \(app.percentLabel)")
                }
                Spacer(minLength: 2)
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").accessibilityHidden(true)
                    TextField("Nom ou PID", text: $query).textFieldStyle(.plain)
                        .accessibilityLabel("Rechercher un processus")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Effacer la recherche")
                    }
                }
                .font(AppFont.caption).padding(.horizontal, 8).frame(width: 180, height: 26)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            let visibleRows = rows
            table(visibleRows)
            if let message = controller.message {
                Text(message).font(AppFont.caption).frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
        }
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: Radius.card))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.white.opacity(0.1)).allowsHitTesting(false))
        .onReceive(controller.$processes) { processes in
            updateOrder(processes)
            highCPUApps = HomeCPUApplication.leaders(in: processes)
        }
        .onChange(of: sort) { _ in updateOrder(controller.processes) }
        .alert("Quitter ce processus ?", isPresented: Binding(get: { quitTarget != nil }, set: { if !$0 { quitTarget = nil } }), presenting: quitTarget) { target in
            Button("Annuler", role: .cancel) {}
            Button("Quitter", role: .destructive) { controller.quit(target) }
        } message: { target in
            Text("Demander la fermeture de \(target.name) (PID \(target.id.pid)) ?")
        }
    }

    private func table(_ visibleRows: [TrayProcess]) -> some View {
        Table(visibleRows, sortOrder: $sort) {
            TableColumn("Nom", value: \TrayProcess.name) { process in
                processName(process)
            }.width(min: 145, ideal: 260)
            TableColumn("Mémoire", value: \TrayProcess.memory) { process in
                Text(humanSize(process.memory, fractionalAbove: 1_000_000_000)).monospacedDigit()
            }.width(min: 106, ideal: 118, max: 140)
            TableColumn("CPU", value: \TrayProcess.sortableCPU) { process in
                HStack(spacing: 8) {
                    ProgressView(value: min(100, process.cpuPercent ?? 0), total: 100)
                        .progressViewStyle(.linear).frame(width: 36).tint(Theme.accentInk).accessibilityHidden(true)
                    Text(metric(process.cpuPercent, unit: "%")).monospacedDigit()
                }.help("100 % correspond à un cœur utilisé.")
            }.width(min: 108, ideal: 124, max: 150)
            TableColumn("Puissance", value: \TrayProcess.sortablePower) { process in
                Text(metric(process.energyWatts, unit: "W")).monospacedDigit()
                    .help("Puissance moyenne estimée par macOS sur le dernier intervalle de mesure.")
            }.width(min: 80, ideal: 98, max: 125)
            TableColumn("PID", value: \TrayProcess.id.pid) { process in
                Text(String(process.id.pid)).monospacedDigit()
            }.width(min: 55, ideal: 65, max: 82)
            TableColumn("") { process in
                actions(for: process)
            }.width(36)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        // Le fond sombre de l’en-tête AppKit laisse apparaître la surface violette de la carte.
        .blendMode(.lighten)
        .frame(minHeight: 82, maxHeight: .infinity)
        .overlay {
            if visibleRows.isEmpty {
                Text(query.isEmpty ? "Lecture des processus accessibles…" : "Aucun processus correspondant")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted).allowsHitTesting(false)
            }
        }
    }

    private func processName(_ process: TrayProcess) -> some View {
        HStack(spacing: 7) {
            if let icon = controller.presentation(for: process).icon {
                Image(nsImage: icon).resizable().scaledToFit().frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "gearshape").frame(width: 16).accessibilityHidden(true)
            }
            Text(process.name).lineLimit(1).truncationMode(.middle)
        }.help(process.executable.isEmpty ? process.name : process.executable)
    }

    private func metric(_ value: Double?, unit: String) -> String {
        guard let value else { return "—" }
        if unit == "W", value > 0 && value < 0.01 { return "< 0,01 W" }
        let precision = unit == "W" && value > 0 && value < 1 ? 2 : 1
        return value.formatted(.number.precision(.fractionLength(precision))) + " " + unit
    }

    private func actions(for process: TrayProcess) -> some View {
        Menu {
            Button("Copier le PID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(process.id.pid), forType: .string)
            }
            if !process.executable.isEmpty {
                Button("Afficher dans le Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: process.executable)])
                }
            }
            Divider()
            Button("Quitter…") { quitTarget = process }
                .disabled(!process.canQuit || controller.pending.contains(process.id))
        } label: {
            Image(systemName: "ellipsis").frame(width: 24, height: 20)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .accessibilityLabel("Actions pour \(process.name), PID \(process.id.pid)")
    }
}

private extension TrayProcess {
    var sortableCPU: Double { cpuPercent ?? -1 }
    var sortablePower: Double { energyWatts ?? -1 }
}

struct HomeCPUApplication: Identifiable {
    let id: URL
    let cpu: Double
    var name: String { id.deletingPathExtension().lastPathComponent }
    var percentLabel: String { cpu.formatted(.number.precision(.fractionLength(0...1))) + " %" }

    static func leaders(in processes: [TrayProcess]) -> [Self] {
        var totals: [URL: Double] = [:]
        for process in processes {
            guard let cpu = process.cpuPercent, cpu.isFinite, cpu > 0,
                  let app = TrayProcessIconResolver.owningApplication(in: process.executable) else { continue }
            totals[app, default: 0] += cpu
        }
        var ranked: [HomeCPUApplication] = []
        for (app, cpu) in totals where cpu > 40 {
            ranked.append(HomeCPUApplication(id: app, cpu: cpu))
        }
        ranked.sort { lhs, rhs in
            if lhs.cpu == rhs.cpu { return lhs.id.path < rhs.id.path }
            return lhs.cpu > rhs.cpu
        }
        return Array(ranked.prefix(3))
    }
}
