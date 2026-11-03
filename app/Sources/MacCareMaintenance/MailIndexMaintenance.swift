import CSQLite
import Darwin
import Foundation

public enum MailIndexMaintenance {
    public enum MailError: LocalizedError {
        case invalid(String)
        public var errorDescription: String? {
            if case .invalid(let message) = self { return message }
            return nil
        }
    }

    /// Seul le magasin Mail de version la plus récente est visé ; aucune création de base.
    public static func locate(home: URL) throws -> URL {
        let root = home.appendingPathComponent("Library/Mail", isDirectory: true)
        let entries: [URL]
        do { entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) }
        catch { throw MailError.invalid("Le dossier Mail est absent ou inaccessible. Vérifiez l’Accès complet au disque.") }
        let versions = entries.compactMap { url -> (Int, URL)? in
            let name = url.lastPathComponent
            guard name.first == "V", let number = Int(name.dropFirst()) else { return nil }
            return (number, url)
        }.sorted { $0.0 > $1.0 }
        guard let latest = versions.first else { throw MailError.invalid("Aucun magasin Mail compatible n’a été trouvé.") }
        let url = latest.1.appendingPathComponent("MailData/Envelope Index")
        try validate(url, home: home)
        return url
    }

    private static func validate(_ url: URL, home: URL) throws {
        let expectedParent = url.deletingLastPathComponent()
        guard url.lastPathComponent == "Envelope Index",
              expectedParent.lastPathComponent == "MailData",
              url.standardizedFileURL.path.hasPrefix(home.standardizedFileURL.path + "/Library/Mail/"),
              url.resolvingSymlinksInPath().path == url.standardizedFileURL.path else {
            throw MailError.invalid("Emplacement de l’index Mail refusé (lien symbolique ou chemin inattendu).")
        }
        for suffix in ["", "-wal", "-shm", "-journal"] {
            var info = stat()
            let code = lstat(url.path + suffix, &info)
            if code != 0 {
                if suffix != "" && errno == ENOENT { continue }
                throw MailError.invalid("Index Mail inaccessible. Vérifiez l’Accès complet au disque.")
            }
            guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_nlink == 1 else {
                throw MailError.invalid("Index Mail refusé : le fichier doit appartenir à votre compte, sans lien.")
            }
        }
    }

    /// SQLite assure l’atomicité de VACUUM. Aucun fichier Mail n’est supprimé manuellement.
    public static func compact(home: URL, isMailRunning: () -> Bool) -> MaintenanceReport {
        var compacted = false
        do {
            guard !isMailRunning() else { throw MailError.invalid("Quittez Mail avant de lancer cette tâche.") }
            let url = try locate(home: home)
            let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            let free = (try home.resourceValues(forKeys: [.volumeAvailableCapacityKey])).volumeAvailableCapacity ?? 0
            guard Int64(free) > Int64(size) * 2 + 1_073_741_824 else {
                throw MailError.invalid("Espace libre insuffisant pour compacter l’index avec une marge de sécurité.")
            }
            var db: OpaquePointer?
            let status = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW, nil)
            defer { if let db { sqlite3_close(db) } }
            guard status == SQLITE_OK, let db else { throw MailError.invalid("Impossible d’ouvrir l’index Mail existant en écriture.") }
            sqlite3_busy_timeout(db, 1500)
            let deadline = Deadline(seconds: 300)
            sqlite3_progress_handler(db, 2000, { context in
                guard let context else { return 1 }
                let deadline = Unmanaged<Deadline>.fromOpaque(context).takeUnretainedValue()
                return ProcessInfo.processInfo.systemUptime >= deadline.uptime ? 1 : 0
            }, Unmanaged.passUnretained(deadline).toOpaque())
            defer { sqlite3_progress_handler(db, 0, nil, nil); withExtendedLifetime(deadline) {} }
            guard try scalar(db, "PRAGMA quick_check(1);") == "ok" else {
                throw MailError.invalid("L’index Mail présente une anomalie. Aucune optimisation n’a été lancée.")
            }
            guard try scalar(db, "SELECT count(*) FROM pragma_table_info('messages') WHERE pk > 0;") == "1",
                  try scalar(db, "SELECT count(*) FROM pragma_table_info('messages') WHERE pk = 1 AND upper(type) = 'INTEGER';") == "1" else {
                throw MailError.invalid("Le format d’identification des messages n’est pas reconnu. L’index ne sera pas compacté.")
            }
            let count = try scalar(db, "SELECT count(*) FROM messages;")
            guard !isMailRunning() else { throw MailError.invalid("Mail a été rouvert. Fermez-le et réessayez.") }
            try execute(db, "VACUUM;")
            compacted = true
            try execute(db, "PRAGMA optimize;")
            guard try scalar(db, "PRAGMA quick_check(1);") == "ok",
                  try scalar(db, "SELECT count(*) FROM messages;") == count else {
                return .init(.partial, "Compactage effectué, mais le contrôle final a échoué. Vérifiez Mail avant de réessayer.")
            }
            return .init(.completed, "Index Mail compacté et contrôlé. Vous pouvez rouvrir Mail.",
                         details: "Intégrité SQLite vérifiée ; nombre de messages indexés conservé.")
        } catch { return .init(compacted ? .partial : .failed, error.localizedDescription) }
    }

    private static func execute(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw MailError.invalid("SQLite a refusé ou interrompu l’opération (base occupée, espace ou intégrité). Aucun fichier de messages n’a été supprimé.")
        }
    }

    private static func scalar(_ db: OpaquePointer, _ sql: String) throws -> String {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MailError.invalid("Format d’index Mail non pris en charge. Aucune réparation ne sera forcée.")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else {
            throw MailError.invalid("Impossible de contrôler l’index Mail.")
        }
        return String(cString: value)
    }

    private final class Deadline {
        let uptime: TimeInterval
        init(seconds: TimeInterval) { uptime = ProcessInfo.processInfo.systemUptime + seconds }
    }
}
