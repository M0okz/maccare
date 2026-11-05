import Foundation

enum AdditionalAlertKind: String, CaseIterable, Identifiable {
    case protection, cpu, cycle
    var id: String { rawValue }
    var enabledKey: String { "additionalAlert.\(rawValue).enabled" }
    var title: String {
        switch self {
        case .protection: return "Protection batterie interrompue"
        case .cpu: return "CPU fortement sollicité"
        case .cycle: return "Fin d’opération batterie"
        }
    }
    static let previewNotification = Notification.Name("MacCare.previewAdditionalAlert")
}
