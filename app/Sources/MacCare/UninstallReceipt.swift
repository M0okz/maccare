import SwiftUI

struct UninstallReceipt: Identifiable {
    enum Status: String, CaseIterable { case failed = "En échec", removed = "Retirés", kept = "Conservés" }
    struct Entry: Identifiable {
        let item: ScanItem
        let status: Status
        let reason: String?
        var id: String { item.path }
    }
    let id = UUID()
    let name: String
    let entries: [Entry]
    let direct: Bool

    init(app: AppInfo, inventory: [ScanItem], chosen: [ScanItem], review: UninstallReview?, report: RemovalReport) {
        name = app.name
        direct = report.direct
        let selected = Set(chosen.map(\.path))
        entries = inventory.map { item in
            if let failure = report.failed.first(where: { $0.path == item.path }) {
                return Entry(item: item, status: .failed, reason: failure.error)
            }
            if let kept = (report.kept + report.refused).first(where: { $0.path == item.path }) {
                return Entry(item: item, status: .kept, reason: RemovalReport.explain(kept.reason))
            }
            if selected.contains(item.path) { return Entry(item: item, status: .removed, reason: nil) }
            let use = review?.use(of: item)
            return Entry(item: item, status: .kept, reason: use?.canRemove == false ? use?.reason : "Non sélectionné.")
        }
    }

    var summary: String {
        let removed = entries.filter { $0.status == .removed }
        var parts = ["\(removed.count) \(direct ? pl(removed.count, "supprimé") : "mis à la corbeille")"]
        let kept = entries.filter { $0.status == .kept }.count
        let failed = entries.filter { $0.status == .failed }.count
        if kept > 0 { parts.append("\(kept) \(pl(kept, "conservé"))") }
        if failed > 0 { parts.append("\(failed) en échec") }
        return parts.joined(separator: " · ")
    }
}

struct UninstallReceiptView: View {
    let receipt: UninstallReceipt
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Bilan de désinstallation · \(receipt.name)").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    ForEach(UninstallReceipt.Status.allCases, id: \.self) { status in
                        let rows = receipt.entries.filter { $0.status == status }
                        if !rows.isEmpty {
                            let size = rows.reduce(UInt64(0)) { $0 + $1.item.size_bytes }
                            Text("\(status.rawValue) · \(rows.count) · \(humanSize(size))").font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(rows) { entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(entry.item.url.lastPathComponent).font(.body.weight(.medium))
                                        Spacer()
                                        Text(humanSize(entry.item.size_bytes)).font(.callout).monospacedDigit()
                                    }
                                    Text(entry.item.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    if let reason = entry.reason {
                                        Text(reason).font(.callout).textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(Space.xl).frame(minWidth: 500, idealWidth: 600, minHeight: 320, idealHeight: 440)
    }
}
