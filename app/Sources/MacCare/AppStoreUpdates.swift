import Foundation

/// Lecture seule du catalogue App Store avec la version de mas livrée dans le paquet.
enum AppStoreUpdates {
    static let storeURL = URL(fileURLWithPath: "/System/Applications/App Store.app")

    static func executableURL(in bundleURL: URL) -> URL? {
        let url = bundleURL.appendingPathComponent("Contents/Helpers/mas")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static func check(
        bundleURL: URL = Bundle.main.bundleURL,
        run: (String, [String]) -> SystemTools.Output = { SystemTools.run($0, $1) }
    ) -> (String, UpdateSource.State, [OutdatedItem]) {
        guard let executable = executableURL(in: bundleURL) else {
            return ("mas", .error("Le composant App Store est absent. Réinstallez MacCare."), [])
        }
        // Le mode accurate commence puis annule des téléchargements : il reste exclu.
        let output = run(executable.path, ["outdated", "--inaccurate", "--json"])
        guard output.ok else {
            return ("mas", .error("App Store indisponible. Réessayez la vérification."), [])
        }
        do {
            return ("mas", .ok, try parse(output.stdout))
        } catch {
            return ("mas", .error("Résultat App Store illisible. Réessayez la vérification."), [])
        }
    }

    static func parse(_ output: String) throws -> [OutdatedItem] {
        struct Update: Decodable {
            let name: String
            let version: String
            let newVersion: String
            let adamID: UInt64?
        }
        let decoder = JSONDecoder()
        return try output.split(whereSeparator: \.isNewline).compactMap { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let update = try decoder.decode(Update.self, from: Data(line.utf8))
            guard !update.name.isEmpty, !update.version.isEmpty, !update.newVersion.isEmpty else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Mise à jour incomplète"))
            }
            return OutdatedItem(name: update.name, detail: "\(update.version) → \(update.newVersion)", storeID: update.adamID.flatMap { $0 > 0 ? $0 : nil })
        }
    }
}
