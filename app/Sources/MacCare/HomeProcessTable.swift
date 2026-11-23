import AppKit
import SwiftUI

/// Le tableau et la carte Batterie utilisent le même relevé.
struct HomeProcessTable: View {
    @ObservedObject var controller: TrayProcessController
    @State private var query = ""
    @State private var groups: [HomeProcessGroup] = []
    @State private var highCPUApps: [HomeProcessGroup] = []
    @State private var sort = HomeProcessSort()
    private struct Selection: Identifiable {
        let group: HomeProcessGroup
        let member: TrayProcess.Identity?
        var id: HomeProcessGroup.ID { group.id }
    }
    @State private var detail: Selection?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Processus").font(.headline).accessibilityAddTraits(.isHeader)
                Text(controller.processes.count.formatted()).font(AppFont.caption).monospacedDigit()
                    .foregroundStyle(Theme.muted).accessibilityLabel("\(controller.processes.count) processus accessibles")
                ForEach(highCPUApps) { app in
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").font(.caption2)
                        Text(app.name).lineLimit(1)
                        Text(HomeProcessMetric.cpu(app.cpu)).monospacedDigit().fixedSize()
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.warn)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.warn.opacity(0.10), in: Capsule())
                    .help("\(app.name) · charge CPU élevée, auxiliaires compris.")
                }
                Spacer(minLength: 2)
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").accessibilityHidden(true)
                    TextField("Nom ou PID", text: $query).textFieldStyle(.plain)
                        .accessibilityLabel("Rechercher un processus")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plainAction).accessibilityLabel("Effacer la recherche")
                    }
                }
                .font(AppFont.caption).padding(.horizontal, 8).frame(width: 180, height: 26)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)

            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let rows = term.isEmpty ? groups : groups.filter { $0.matches(term) }
            HomeProcessList(rows: rows, controller: controller, sort: $sort) { group in
                detail = Selection(group: group, member: group.members.first { String($0.id.pid) == term }?.id)
            }
                .frame(minHeight: 82, maxHeight: .infinity)
                .overlay {
                    if rows.isEmpty {
                        Text(term.isEmpty ? "Lecture des processus accessibles…" : "Aucun processus correspondant")
                            .font(AppFont.secondary).foregroundStyle(Theme.muted).allowsHitTesting(false)
                    }
                }
            if let message = controller.message {
                Text(message).font(AppFont.caption).frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
        }
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: Radius.card))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.white.opacity(0.1)).allowsHitTesting(false))
        .onReceive(controller.$processes) { processes in
            let snapshot = HomeProcessGroup.collect(processes, registered: HomeProcessGroup.registeredApplications())
            groups = sort.ordered(snapshot)
            highCPUApps = HomeProcessSort.highCPUApplications(in: snapshot)
        }
        .onChange(of: sort) { groups = $0.ordered(groups) }
        .sheet(item: $detail) { opened in
            HomeProcessDetails(opened: opened.group, matchedPID: opened.member, group: groups.first { $0.id == opened.id }, controller: controller)
        }
    }
}

enum HomeProcessColumn: String, CaseIterable {
    case name = "Nom", memory = "Mémoire", cpu = "CPU", power = "Puissance", pid = "PID"
}

struct HomeProcessSort: Equatable {
    var column: HomeProcessColumn = .memory
    var ascending = false

    static func highCPUApplications(in groups: [HomeProcessGroup]) -> [HomeProcessGroup] {
        let apps = groups.filter { $0.highCPU && $0.application != nil }
        return Array(HomeProcessSort(column: .cpu).ordered(apps).prefix(3))
    }

    func ordered(_ rows: [HomeProcessGroup]) -> [HomeProcessGroup] {
        rows.sorted { left, right in
            let (a, b) = ascending ? (left, right) : (right, left)
            switch column {
            case .name:
                let order = a.name.localizedStandardCompare(b.name)
                if order != .orderedSame { return order == .orderedAscending }
            case .memory: if a.memory != b.memory { return a.memory < b.memory }
            case .cpu: if a.cpu != b.cpu { return (a.cpu ?? -1) < (b.cpu ?? -1) }
            case .power: if a.power != b.power { return (a.power ?? -1) < (b.power ?? -1) }
            case .pid:
                let ap = a.primary?.id.pid ?? -1, bp = b.primary?.id.pid ?? -1
                if ap != bp { return ap < bp }
            }
            if left.application?.path != right.application?.path {
                return (left.application?.path ?? "") < (right.application?.path ?? "")
            }
            return left.members[0].id.pid < right.members[0].id.pid
        }
    }
}
