import Foundation

/// A helper registered from a disk image or from macOS's temporary copy would lose its program
/// when the image is ejected, possibly while it still holds a charge limit.
enum AppInstallLocation {
    static let instruction = "MacCare est lancé depuis un emplacement temporaire. Glissez-le dans le dossier Applications, puis ouvrez-le depuis ce dossier pour activer l’assistant et recevoir les mises à jour."

    static func isTemporary(path: String, onReadOnlyVolume: Bool) -> Bool {
        onReadOnlyVolume || path.contains("/AppTranslocation/")
    }

    static var isTemporary: Bool {
        let url = Bundle.main.bundleURL
        let readOnly = (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        return isTemporary(path: url.path, onReadOnlyVolume: readOnly)
    }
}
