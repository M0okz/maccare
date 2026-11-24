import SwiftUI

struct SmartScanCleanupView: View {
    let result: SmartScanCleanup
    let busy: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Dernier nettoyage").font(AppFont.emphasis).accessibilityAddTraits(.isHeader)
            Text(result.report.summary)
                .font(AppFont.body).foregroundStyle(result.report.needsAttention ? Theme.warn : Theme.muted)
            if result.report.removed > 0 {
                Text("Taille mesurée des éléments retirés · \(humanSize(result.measuredBytes))")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
            }
            if !result.waiting.isEmpty {
                ForEach(result.appTotals) { total in
                    Text("\(total.id) · \(humanSize(total.bytes)) en attente")
                        .font(AppFont.body).fixedSize(horizontal: false, vertical: true)
                }
                Text("Quittez les applications indiquées pour reprendre le nettoyage de leurs caches.")
                    .font(AppFont.secondary).foregroundStyle(Theme.muted)
                Button("Réessayer ces éléments", action: retry).buttonStyle(.actionPill).disabled(busy)
            }
        }
    }
}
