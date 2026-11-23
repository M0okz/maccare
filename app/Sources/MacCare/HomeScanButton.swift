import SwiftUI

struct HomeScanButton: View {
    @ObservedObject var model: SmartScanModel
    let diameter: CGFloat
    let openCleaning: () -> Void

    private var busy: Bool { model.stage == .scanning || model.stage == .cleaning }

    var body: some View {
        Button(busy ? "Suivre" : "Analyser") {
            if !busy { model.prepareForNewScan() }
            openCleaning()
        }
        .buttonStyle(CircularOverviewActionStyle(tint: VeilleBrand.amethyst, diameter: diameter))
        .accessibilityLabel(busy ? "Suivre le nettoyage" : "Analyser le nettoyage")
        .help(helpText)
    }

    private var helpText: String {
        if busy { return "Suivre l’opération en cours." }
        guard let date = model.lastCompletedAt else { return "Ouvrir la préparation de l’analyse de nettoyage." }
        return "Préparer une nouvelle analyse. Dernière analyse il y a " + ScanAgeText.label(since: date, now: .now) + "."
    }
}
