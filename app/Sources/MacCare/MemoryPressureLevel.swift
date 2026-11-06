import Darwin
import Foundation

enum MemoryPressureLevel: UInt32, Sendable {
    case normal = 1, warning = 2, critical = 4

    var title: String {
        switch self {
        case .normal: return "Pression normale"
        case .warning: return "Pression élevée"
        case .critical: return "Pression critique"
        }
    }

    static func current() -> Self? {
        // XNU exporte les flags Dispatch, pas les valeurs de son enum interne.
        var value: UInt32 = 0
        var size = MemoryLayout<UInt32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0,
              size == MemoryLayout<UInt32>.size else { return nil }
        return Self(rawValue: value)
    }
}
