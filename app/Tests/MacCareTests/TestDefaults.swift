import Foundation

/// Nom de suite pour des préférences de test, conservées dans le dossier temporaire.
///
/// Avec un nom ordinaire, macOS laisse un plist vide dans `~/Library/Preferences`, même après
/// `removePersistentDomain`, et peut le réécrire à la fermeture du processus. Un chemin absolu
/// garde ces fichiers hors du dossier de préférences de l'utilisateur.
func testPreferencesSuite(_ label: String) -> String {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacCareTestPreferences", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("\(label).\(UUID().uuidString)").path
}
