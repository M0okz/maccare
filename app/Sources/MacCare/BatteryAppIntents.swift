import AppIntents
import Foundation
import MacCareBattery

/// One handoff into the same model used by the window. Intents cannot bypass
/// helper capabilities, session ownership, validation, or the recovery journal.
@MainActor
enum BatteryIntentBridge {
    private(set) static weak var model: BatteryModel?
    static func bind(_ model: BatteryModel) { self.model = model }
    static func current() throws -> BatteryModel {
        guard let model else { throw IntentFailure() }
        return model
    }
    private struct IntentFailure: LocalizedError {
        var errorDescription: String? { "Ouvrez MacCare avant d’utiliser ses actions Batterie." }
    }
}

struct SetBatteryLimitIntent: AppIntent {
    static var title: LocalizedStringResource = "Régler la limite de charge"
    static var description = IntentDescription("Applique une limite proposée par ce Mac et conserve les autres réglages de protection.")
    static var openAppWhenRun = true
    @Parameter(title: "Limite en pourcentage", default: 80) var limit: Int
    @MainActor func perform() async throws -> some IntentResult {
        let model = try BatteryIntentBridge.current()
        await model.refresh(force: true)
        var value = model.configuration; value.limit = limit
        try await model.executeAutomation(.configure(value))
        return .result()
    }
}

struct TopUpBatteryIntent: AppIntent {
    static var title: LocalizedStringResource = "Recharger à 100 % une fois"
    static var description = IntentDescription("Suspend temporairement le plafond, puis revient à la limite configurée.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        try await BatteryIntentBridge.current().executeAutomation(.topUp)
        return .result()
    }
}

struct StopBatteryProtectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Désactiver la protection de la batterie"
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        try await BatteryIntentBridge.current().executeAutomation(.disable)
        return .result()
    }
}

struct DischargeBatteryIntent: AppIntent {
    static var title: LocalizedStringResource = "Décharger la batterie jusqu’à la limite"
    static var description = IntentDescription("Le Mac utilise sa batterie tout en restant branché, puis reprend le secteur à la limite. Nécessite une méthode de décharge compatible.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        try await BatteryIntentBridge.current().executeAutomation(.discharge)
        return .result()
    }
}

struct BatteryAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SetBatteryLimitIntent(), phrases: ["Limiter la charge avec \(.applicationName)"],
                    shortTitle: "Limiter la charge", systemImageName: "battery.75percent")
        AppShortcut(intent: TopUpBatteryIntent(), phrases: ["Recharger complètement avec \(.applicationName)"],
                    shortTitle: "Recharger à 100 %", systemImageName: "battery.100.bolt")
        AppShortcut(intent: StopBatteryProtectionIntent(), phrases: ["Désactiver la protection batterie de \(.applicationName)"],
                    shortTitle: "Arrêter la protection", systemImageName: "pause.circle")
    }
}
