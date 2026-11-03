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

enum BatteryCycleIntentAction: String, AppEnum {
    case discharge, calibrate
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Cycle de batterie"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .discharge: "Décharger jusqu’à la limite", .calibrate: "Démarrer l’étalonnage"
    ]
}

struct StartBatteryCycleIntent: AppIntent {
    static var title: LocalizedStringResource = "Démarrer un cycle de batterie"
    static var description = IntentDescription("Décharge vers la limite ou lance un cycle complet d’étalonnage. Nécessite un adaptateur contrôlable.")
    static var openAppWhenRun = true
    @Parameter(title: "Cycle", default: .discharge) var action: BatteryCycleIntentAction
    @MainActor func perform() async throws -> some IntentResult {
        if action == .calibrate {
            try await requestConfirmation(result: .result(dialog: "L’étalonnage recharge à 100 %, décharge jusqu’à 10 %, recharge à 100 %, puis revient à votre limite. Le cycle peut durer plusieurs heures. Continuer ?"))
        }
        try await BatteryIntentBridge.current().executeAutomation(action == .discharge ? .discharge : .calibrate)
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
