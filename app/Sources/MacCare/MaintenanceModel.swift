import Foundation
import SwiftUI

/// Une tâche de maintenance de niveau utilisateur (aucune élévation de privilèges).
struct MaintenanceTask: Identifiable {
    let key: String
    let title: String
    let note: String
    let launch: String
    let args: [String]
    var id: String { key }
    var effect: String {
        switch key {
        case "lsregister": return "MacCare reconstruit la liste des applications associées aux fichiers. Le menu « Ouvrir avec » peut mettre un moment à se mettre à jour. Vos fichiers et vos applications sont conservés."
        case "quicklook": return "macOS recharge son service d’aperçu. Les prochains aperçus pourront prendre un peu plus de temps à s’afficher. Vos fichiers sont conservés."
        default: return "Le cache des polices de votre compte sera supprimé puis reconstruit par macOS. Fermez les applications concernées avant de continuer ; vous pourrez devoir les rouvrir après la réparation."
        }
    }
}

/// Tâches de maintenance sûres, exécutées dans le domaine utilisateur. Les tâches nécessitant
/// `sudo` (index Spotlight système, scripts periodic, purge mémoire, cache DNS) sont volontairement
/// exclues de la v1 : MacCare ne demande pas de privilèges administrateur.
@MainActor
final class MaintenanceModel: ObservableObject {
    @Published private(set) var running: String?
    @Published private(set) var results: [String: (ok: Bool, message: String)] = [:]

    let tasks: [MaintenanceTask] = [
        MaintenanceTask(
            key: "lsregister",
            title: "Corriger le menu « Ouvrir avec »",
            note: "Répare le menu « Ouvrir avec » et les doublons d'applications.",
            launch: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            args: ["-kill", "-r", "-domain", "local", "-domain", "user"]
        ),
        MaintenanceTask(
            key: "quicklook",
            title: "Rétablir les aperçus des fichiers",
            note: "Régénère les vignettes et aperçus si certains s'affichent mal.",
            launch: "/usr/bin/qlmanage",
            args: ["-r"]
        ),
        MaintenanceTask(
            key: "fontcache",
            title: "Corriger l’affichage des polices",
            note: "Résout certains soucis d'affichage de polices.",
            launch: "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/ATS.framework/Support/atsutil",
            args: ["databases", "-removeUser"]
        ),
    ]

    func run(_ task: MaintenanceTask) {
        guard running == nil else { return }
        running = task.key
        results[task.key] = nil
        let launch = task.launch
        let args = task.args
        Task.detached(priority: .userInitiated) {
            let out: (ok: Bool, message: String)
            if !FileManager.default.isExecutableFile(atPath: launch) {
                out = (false, "outil introuvable sur ce système")
            } else {
                let r = SystemTools.run(launch, args)
                if r.ok {
                    out = (true, "Terminé.")
                } else {
                    let msg = r.stderr.isEmpty ? r.stdout : r.stderr
                    out = (false, msg.isEmpty ? "échec (code \(r.status))" : String(msg.prefix(200)))
                }
            }
            await MainActor.run {
                self.results[task.key] = out
                self.running = nil
            }
        }
    }
}
