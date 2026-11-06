import SwiftUI

/// Quatre positions stables, dont les positions vides sont masquées dans le volet.
enum TrayShortcuts {
    static let key = "tray.toolShortcuts"
    static let defaults = "cleaningOverview,performanceOverview,space,maintenance"
    static let available: [Module] = [.cleaningOverview, .performanceOverview, .space, .largeFiles, .duplicates,
        .trash, .uninstall, .startup, .privacy, .updates, .maintenance, .screenCleaning, .aiClutter, .applicationPermissions, .battery]

    static func slots(_ raw: String) -> [Module?] {
        var seen: Set<String> = []
        let values = raw.components(separatedBy: ",")
        return (0..<4).map { index in
            guard index < values.count, let module = Module(rawValue: values[index]), available.contains(module),
                  seen.insert(module.rawValue).inserted else { return nil }
            return module
        }
    }
    static func replacing(_ raw: String, at index: Int, with value: String) -> String {
        guard (0..<4).contains(index) else { return raw }
        var values = slots(raw).map { $0?.rawValue ?? "" }
        if !value.isEmpty {
            for position in values.indices where position != index && values[position] == value { values[position] = "" }
        }
        values[index] = value
        return slots(values.joined(separator: ",")).map { $0?.rawValue ?? "" }.joined(separator: ",")
    }
}

struct TrayShortcutSettingsView: View {
    @AppStorage(TrayShortcuts.key) private var shortcuts = TrayShortcuts.defaults
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choisissez jusqu’à quatre outils, dans leur ordre d’apparition. Un raccourci ouvre l’outil dans MacCare.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(0..<4) { index in
                Picker("Raccourci \(index + 1)", selection: Binding(
                    get: { TrayShortcuts.slots(shortcuts)[index]?.rawValue ?? "" },
                    set: { shortcuts = TrayShortcuts.replacing(shortcuts, at: index, with: $0) }
                )) {
                    Text("Aucun").tag("")
                    ForEach(TrayShortcuts.available) { module in
                        Label(module.title, systemImage: module.symbol).tag(module.rawValue)
                    }
                }
            }
        }
    }
}
