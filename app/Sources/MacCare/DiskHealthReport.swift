import Foundation

struct DiskHealthReport: Sendable {
    let model: String?
    let passed: Bool?
    let warning: Bool
    let temperature: Int?
    let enduranceUsed: Int?
    let spareAvailable: Int?
    let hours: UInt64?
    let powerCycles: UInt64?
    let writtenBytes: UInt64?
    let mediaErrors: UInt64?
    var summary: String {
        if warning { return "Le disque signale une alerte" }
        return passed == true ? "Aucune alerte matérielle signalée" : "État général non communiqué"
    }
}
