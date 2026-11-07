import Foundation

struct PNGOptimizationItem: Identifiable {
    let url: URL
    var originalSize: UInt64
    var result: PNGOptimizationResult?
    var error: String?
    var processing = false
    var id: URL { url }
    var status: String {
        if processing { return "Optimisation en cours…" }
        if let error { return error }
        if let result { return result.output_path == nil ? "Déjà optimisée" : "Copie créée · \(humanSize(result.savedBytes)) de moins" }
        return "Prête à être allégée"
    }
}
