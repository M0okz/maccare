import AppKit
import SwiftUI

/// Le tableau et la carte Batterie utilisent le même relevé.
struct HomeProcessTable: View {
    @ObservedObject var controller: TrayProcessController
    @State private var query = ""
    @State private var isCardHovered = false
    @State private var groups: [HomeProcessGroup] = []
    @State private var cpuSummary = ""
    @State private var sort = HomeProcessSort()
    @EnvironmentObject private var presentation: HomeProcessPresentation

    var body: some View {
        VStack(spacing: 0) {
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let rows = term.isEmpty ? groups : groups.filter { $0.matches(term) }
            HomeProcessList(rows: rows, processCount: controller.processes.count, cpuSummary: cpuSummary,
                            controller: controller, isCardHovered: isCardHovered, sort: $sort, query: $query) { group in
                presentation.open(group, member: group.members.first { String($0.id.pid) == term }, controller: controller)
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
        .onHover { isCardHovered = $0 }
        .onReceive(controller.$processes) { processes in
            let snapshot = HomeProcessGroup.collect(processes, registered: HomeProcessGroup.registeredApplications())
            presentation.refresh(snapshot)
            groups = sort.ordered(snapshot)
            cpuSummary = HomeProcessSort.highCPUApplications(in: snapshot)
                .map { "\($0.name) · \($0.cpuLabel)" }.joined(separator: "\n")
        }
        .onChange(of: sort) { groups = $0.ordered(groups) }
        .onDisappear { presentation.close() }
    }
}

enum HomeProcessColumn: String, CaseIterable {
    case name = "Nom", memory = "Mémoire", cpu = "CPU", power = "Puissance", pid = "PID"
}

struct HomeProcessSort: Equatable {
    var column: HomeProcessColumn = .memory
    var ascending = false

    static func highCPUApplications(in groups: [HomeProcessGroup]) -> [HomeProcessGroup] {
        let apps = groups.filter { $0.cpuLevel != .normal && $0.application != nil }
        return Array(HomeProcessSort(column: .cpu).ordered(apps).prefix(3))
    }

    func ordered(_ rows: [HomeProcessGroup]) -> [HomeProcessGroup] {
        rows.sorted { left, right in
            let (a, b) = ascending ? (left, right) : (right, left)
            switch column {
            case .name:
                let order = a.name.localizedStandardCompare(b.name)
                if order != .orderedSame { return order == .orderedAscending }
            case .memory:
                if (left.memory == nil) != (right.memory == nil) { return left.memory != nil }
                if let am = a.memory, let bm = b.memory, am != bm { return am < bm }
            case .cpu: if a.cpu != b.cpu { return (a.cpu ?? -1) < (b.cpu ?? -1) }
            case .power: if a.power != b.power { return (a.power ?? -1) < (b.power ?? -1) }
            case .pid:
                let ap = a.representative.id.pid, bp = b.representative.id.pid
                if ap != bp { return ap < bp }
            }
            if left.application?.path != right.application?.path {
                return (left.application?.path ?? "") < (right.application?.path ?? "")
            }
            return left.members[0].id.pid < right.members[0].id.pid
        }
    }
}
