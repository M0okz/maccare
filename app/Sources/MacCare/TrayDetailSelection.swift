import Foundation

/// Un seul popover sélectionné, avec les données déjà suivies par le volet.
enum TrayDetailSelection: Identifiable {
    case activity(TrayMetricDetail.Kind)
    case storage
    case battery

    var id: String {
        switch self {
        case .activity(let kind): return "activity-" + kind.id
        case .storage: return "storage"
        case .battery: return "battery"
        }
    }
}
