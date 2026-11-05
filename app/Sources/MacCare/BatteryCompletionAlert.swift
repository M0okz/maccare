import Foundation

struct BatteryCompletionAlert: Equatable {
    enum Operation: String { case topUp, discharge, calibration }
    let id: UUID
    let operation: Operation
    let target: Int
    let createdAt: Date
    var title: String {
        switch operation {
        case .topUp: return "Recharge ponctuelle terminée"
        case .discharge: return "Décharge terminée"
        case .calibration: return "Étalonnage terminé"
        }
    }
}
