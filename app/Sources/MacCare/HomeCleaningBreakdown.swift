import Foundation

/// Répartition du seul espace régénérable qui compose le total de l’accueil.
struct HomeCleaningBreakdown: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case caches, temporary, logs, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .caches: return "Caches"
            case .temporary: return "Fichiers temporaires"
            case .logs: return "Journaux"
            case .other: return "Autres"
            }
        }
        var symbol: String {
            switch self {
            case .caches: return "square.3.layers.3d"
            case .temporary: return "doc"
            case .logs: return "list.bullet"
            case .other: return "archivebox"
            }
        }
        fileprivate init(category: String) {
            if category.contains("cache") { self = .caches }
            else if category == "logs" || category.hasSuffix("-logs") { self = .logs }
            else if category.contains("temp") { self = .temporary }
            else { self = .other }
        }
    }

    struct Part: Identifiable, Equatable {
        let kind: Kind
        let bytes: UInt64
        var id: Kind { kind }
    }

    let parts: [Part]
    var total: UInt64 { parts.reduce(0) { $0 + $1.bytes } }
    var stored: [String: NSNumber] {
        Dictionary(uniqueKeysWithValues: parts.map { ($0.kind.rawValue, NSNumber(value: $0.bytes)) })
    }

    init(groups: [ScanGroup]) {
        var amounts: [Kind: UInt64] = [:]
        for group in groups where group.category.risk == .safe {
            amounts[Kind(category: group.category.category), default: 0] += group.size
        }
        parts = Kind.allCases.compactMap { kind in
            guard let bytes = amounts[kind], bytes > 0 else { return nil }
            return Part(kind: kind, bytes: bytes)
        }
    }

    /// Un ancien bilan sans détail ou un détail incohérent reste indisponible.
    init?(stored: Any?, total expectedTotal: UInt64) {
        guard let values = stored as? [String: Any] else { return nil }
        var amounts: [Kind: UInt64] = [:], total: UInt64 = 0
        for (key, raw) in values {
            guard let kind = Kind(rawValue: key), let number = raw as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let bytes = UInt64(number.stringValue) else { return nil }
            let sum = total.addingReportingOverflow(bytes)
            guard !sum.overflow else { return nil }
            total = sum.partialValue
            amounts[kind] = bytes
        }
        guard total == expectedTotal else { return nil }
        parts = Kind.allCases.compactMap { kind in
            guard let bytes = amounts[kind], bytes > 0 else { return nil }
            return Part(kind: kind, bytes: bytes)
        }
    }
}
