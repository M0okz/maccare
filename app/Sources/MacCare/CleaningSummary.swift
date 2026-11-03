import Foundation

/// Le bilan n’annonce jamais un Mac propre sur la base d’une analyse partielle.
struct CleaningSummary {
    let isComplete: Bool
    let wasCancelled: Bool
    let isCleaning: Bool
    let foundSize: UInt64

    var isPartial: Bool { !isComplete || wasCancelled }
    var title: String {
        if isCleaning { return "Nettoyage en cours" }
        if isPartial { return "Résultats partiels" }
        return foundSize == 0 ? "Aucun élément détecté" : "\(humanSize(foundSize)) à examiner"
    }
    var detail: String {
        if isCleaning { return "Consultez le détail de l’opération dans les résultats." }
        if isPartial { return "\(humanSize(foundSize)) détectés avant l’arrêt. Relancez l’analyse pour compléter le bilan." }
        return "Dans les catégories analysées. Examinez les éléments avant de choisir ce que vous souhaitez retirer."
    }
}
