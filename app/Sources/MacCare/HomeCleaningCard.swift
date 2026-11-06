import SwiftUI

struct HomeCleaningCard: View {
    @ObservedObject var model: SmartScanModel
    let onAnalyze: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var metricSize = 40
    private var scanning: Bool { model.stage == .scanning }
    private var busy: Bool { scanning || model.stage == .cleaning }
    private var breakdown: HomeCleaningBreakdown? {
        guard !busy, !model.wasCancelled else { return nil }
        return model.isComplete ? HomeCleaningBreakdown(groups: model.groups) : model.lastBreakdown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label(scanning ? "Analyse en cours" : "Bilan du nettoyage", systemImage: "sparkles")
                    .font(.headline).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if let last = model.lastCompletedAt, !busy {
                    ScanAgeText(date: last).font(AppFont.caption).foregroundStyle(Theme.muted)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    summary.frame(width: 300, alignment: .leading)
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 72).accessibilityHidden(true)
                    distribution.frame(maxWidth: .infinity, alignment: .leading)
                    analyzeButton
                }.frame(minWidth: 900)
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 20) {
                        summary.frame(maxWidth: .infinity, alignment: .leading)
                        analyzeButton
                    }
                    distribution
                }
            }
            Divider().overlay(.white.opacity(0.08))
            Label {
                Text("Analyse seule. Vous choisissez chaque suppression.")
            } icon: {
                Image(systemName: "shield").accessibilityHidden(true)
            }.font(AppFont.secondary).foregroundStyle(Theme.muted)
        }
        .padding(24).frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [ModuleColor.clean.opacity(0.24), .white.opacity(0.035)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.12)))
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metric).font(.system(size: metricSize, weight: .semibold)).monospacedDigit()
                .accessibilityAddTraits(.isHeader)
            Text(detail).font(AppFont.body).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var analyzeButton: some View {
        Button(busy ? "Suivre" : "Analyser", action: onAnalyze)
            .buttonStyle(CircularOverviewActionStyle(tint: ModuleColor.clean))
            .accessibilityLabel(busy ? "Suivre le nettoyage" : "Analyser le nettoyage")
            .help(busy ? "Ouvrir l’opération en cours." : "Revenir à l’écran Analyser pour préparer un nouveau bilan.")
    }

    @ViewBuilder private var distribution: some View {
        if scanning {
            VStack(alignment: .leading, spacing: 12) {
                ProgressView(value: model.progress).accessibilityLabel("Progression de l’analyse")
                Button("Arrêter l’analyse") { model.cancelScan() }.buttonStyle(LinkStyle())
            }
        } else if let breakdown, breakdown.total > 0 {
            HomeCleaningDistribution(breakdown: breakdown)
        } else if !busy && !model.wasCancelled && model.lastCompletedAt != nil && !model.isComplete {
            Text("La répartition sera disponible après la prochaine analyse.")
                .font(AppFont.secondary).foregroundStyle(Theme.muted)
        }
    }

    private var metric: String {
        if scanning { return "On fait le point…" }
        if model.stage == .cleaning { return "Nettoyage en cours" }
        if model.wasCancelled { return "Analyse interrompue" }
        if model.isComplete { return humanSize(model.safeSize) }
        if model.lastCompletedAt != nil { return humanSize(model.lastSafeBytes) }
        return "Faites place nette"
    }
    private var detail: String {
        if scanning { return model.currentLabel ?? "Recherche des éléments récupérables…" }
        if model.stage == .cleaning { return "Consultez le bilan pour suivre l’opération." }
        if model.wasCancelled { return "Relancez l’analyse pour obtenir un bilan complet." }
        if model.isComplete { return "récupérables dans le bilan actuel" }
        if model.lastCompletedAt != nil { return "repérés lors de la dernière analyse" }
        return "Repérez les caches et journaux régénérables de votre Mac."
    }
}
