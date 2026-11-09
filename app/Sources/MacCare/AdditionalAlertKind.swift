import Foundation

enum AdditionalAlertKind: String, CaseIterable, Identifiable {
    case protection, cpu, cycle, deviceBattery
    var id: String { rawValue }
    var enabledByDefault: Bool { self != .deviceBattery }
    var enabledKey: String { "additionalAlert.\(rawValue).enabled" }
    var title: String {
        switch self {
        case .protection: return "Protection batterie interrompue"
        case .cpu: return "CPU fortement sollicité"
        case .cycle: return "Fin d’opération batterie"
        case .deviceBattery: return "Batterie faible des appareils"
        }
    }
    static let previewNotification = Notification.Name("MacCare.previewAdditionalAlert")
}
