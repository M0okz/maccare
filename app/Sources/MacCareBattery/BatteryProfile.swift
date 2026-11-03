import Foundation

public struct BatteryProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var configuration: BatteryConfiguration
    public init(id: UUID = UUID(), name: String, configuration: BatteryConfiguration) {
        self.id = id; self.name = name; self.configuration = configuration
    }
    public var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 60 && configuration.isValid }
    public static var presets: [Self] {
        [Self(id: UUID(uuidString: "B6D80C80-99ED-4C26-A923-C2E8700B0070")!, name: "Sur secteur", configuration: .init(limit: 70, thermalProtection: false, sailingWidth: 10)),
         Self(id: UUID(uuidString: "B6D80C80-99ED-4C26-A923-C2E8700B0080")!, name: "Usage mixte", configuration: .init(limit: 80, thermalProtection: false, sailingWidth: 5)),
         Self(id: UUID(uuidString: "B6D80C80-99ED-4C26-A923-C2E8700B0100")!, name: "Déplacement", configuration: .init(limit: 100, thermalProtection: false))]
    }
    public func unavailableReason(for capabilities: BatteryControlCapabilities?) -> String? {
        guard let capabilities, capabilities.isValid else { return "Actualisez le contrôle de charge pour vérifier ce profil." }
        guard capabilities.supportedLimits.contains(configuration.limit) else { return "La limite de \(configuration.limit) % n’est pas disponible sur ce Mac." }
        if configuration.sailingWidth != nil && !capabilities.supportsSailing { return "La plage de maintien personnalisée n’est pas disponible avec ce contrôleur." }
        if configuration.thermalProtection && !capabilities.supportsThermalProtection { return "La pause thermique personnalisée n’est pas disponible avec ce contrôleur." }
        return nil
    }
}
