import Foundation
import CSQLite
import MacCareMaintenance
import Darwin

struct ApplicationPermission: Identifiable, Hashable {
    let service: String
    let client: String
    let clientType: Int
    let authorization: Int
    let target: String
    let system: Bool
    let managed: Bool
    var id: String { "\(system)|\(service)|\(clientType)|\(client)|\(target)" }
    var granted: Bool { authorization == 2 || authorization == 3 }
    var state: String {
        switch authorization {
        case 0: return "Refusée"
        case 1: return "À demander"
        case 2: return "Autorisée"
        case 3: return "Accès limité"
        default: return "État inconnu"
        }
    }
    var canReset: Bool {
        !system && !managed && clientType == 0 && granted &&
        ApplicationPermissionStore.resettable.contains(service) && ApplicationPermissionStore.validBundleID(client)
    }
    var title: String { ApplicationPermissionStore.services[service]?.title ?? service.replacingOccurrences(of: "kTCCService", with: "") }
    var settingsPane: String { ApplicationPermissionStore.services[service]?.pane ?? "Privacy" }
}

struct ApplicationPermissionSnapshot {
    var entries: [ApplicationPermission] = []
    var warnings: [String] = []
    var readableDatabases = 0
}

/// Lecture SQLite uniquement. Les changements passent par tccutil ou les Réglages Système.
enum ApplicationPermissionStore {
    static let services: [String: (title: String, pane: String)] = [
        "kTCCServiceAccessibility": ("Accessibilité", "Privacy_Accessibility"),
        "kTCCServiceSystemPolicyAllFiles": ("Accès complet au disque", "Privacy_AllFiles"),
        "kTCCServiceScreenCapture": ("Enregistrement d’écran", "Privacy_ScreenCapture"),
        "kTCCServiceListenEvent": ("Surveillance de l’entrée", "Privacy_ListenEvent"),
        "kTCCServiceCamera": ("Caméra", "Privacy_Camera"),
        "kTCCServiceMicrophone": ("Microphone", "Privacy_Microphone"),
        "kTCCServiceAddressBook": ("Contacts", "Privacy_Contacts"),
        "kTCCServiceCalendar": ("Calendriers", "Privacy_Calendars"),
        "kTCCServiceReminders": ("Rappels", "Privacy_Reminders"),
        "kTCCServicePhotos": ("Photos", "Privacy_Photos"),
        "kTCCServiceAppleEvents": ("Automatisation", "Privacy_Automation"),
        "kTCCServiceSystemPolicyDesktopFolder": ("Bureau", "Privacy_FilesAndFolders"),
        "kTCCServiceSystemPolicyDocumentsFolder": ("Documents", "Privacy_FilesAndFolders"),
        "kTCCServiceSystemPolicyDownloadsFolder": ("Téléchargements", "Privacy_FilesAndFolders"),
        "kTCCServiceSystemPolicyNetworkVolumes": ("Volumes réseau", "Privacy_FilesAndFolders"),
        "kTCCServiceSystemPolicyRemovableVolumes": ("Volumes amovibles", "Privacy_FilesAndFolders"),
        "kTCCServiceBluetoothAlways": ("Bluetooth", "Privacy_Bluetooth"),
        "kTCCServiceMediaLibrary": ("Médias", "Privacy_Media"),
        "kTCCServiceSpeechRecognition": ("Reconnaissance vocale", "Privacy_SpeechRecognition"),
        "kTCCServiceDeveloperTool": ("Outils de développement", "Privacy_DeveloperTools")
    ]
    static let resettable: Set<String> = Set([
        "Camera", "Microphone", "AddressBook", "Calendar", "Reminders", "Photos",
        "SystemPolicyDesktopFolder", "SystemPolicyDocumentsFolder", "SystemPolicyDownloadsFolder",
        "SystemPolicyNetworkVolumes", "SystemPolicyRemovableVolumes", "SpeechRecognition", "MediaLibrary"
    ].map { "kTCCService" + $0 })

    static func validBundleID(_ value: String) -> Bool {
        value.contains(".") && value.count <= 255 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-").contains($0)
        }
    }

    static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ApplicationPermissionSnapshot {
        var result = ApplicationPermissionSnapshot()
        for (path, system) in [
            (home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path, false),
            ("/Library/Application Support/com.apple.TCC/TCC.db", true)
        ] {
            var metadata = stat()
            // Certaines versions de macOS n'ont plus de base utilisateur distincte.
            // ENOENT est une absence ; EPERM/EACCES reste une lecture indisponible.
            if lstat(path, &metadata) != 0 && errno == ENOENT { continue }
            do {
                result.entries += try read(path: path, system: system)
                result.readableDatabases += 1
            } catch {
                result.warnings.append("\(system ? "Autorisations système" : "Autorisations utilisateur") : \(error.localizedDescription)")
            }
        }
        if result.readableDatabases == 0 && result.warnings.isEmpty {
            result.warnings = ["Aucune base d’autorisations accessible n’a été trouvée. Consultez les Réglages Système."]
        }
        return result
    }

    static func read(path: String, system: Bool) throws -> [ApplicationPermission] {
        var db: OpaquePointer?
        let status = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        defer { if let db { sqlite3_close(db) } }
        guard status == SQLITE_OK, let db else {
            throw failure("Lecture indisponible. Vérifiez l’Accès complet au disque de MacCare, puis relancez l’application.")
        }
        sqlite3_busy_timeout(db, 1000)
        var columns: Set<String> = []
        try rows(db, sql: "PRAGMA table_info(access)") { statement in columns.insert(string(statement, 1)) }
        guard columns.isSuperset(of: ["service", "client", "client_type"]), columns.contains("auth_value") || columns.contains("allowed") else {
            throw failure("Ce format d’autorisations macOS n’est pas pris en charge. Utilisez les Réglages Système.")
        }
        let auth = columns.contains("auth_value") ? "auth_value" : "CASE WHEN allowed = 1 THEN 2 ELSE 0 END"
        let target = columns.contains("indirect_object_identifier") ? "indirect_object_identifier" : "''"
        let reason = columns.contains("auth_reason") ? "auth_reason" : "0"
        var entries: [ApplicationPermission] = []
        try rows(db, sql: "SELECT service, client, client_type, \(auth), \(target), \(reason) FROM access") { s in
            let reason = sqlite3_column_int(s, 5)
            entries.append(.init(service: string(s, 0), client: string(s, 1), clientType: Int(sqlite3_column_int(s, 2)),
                                 authorization: Int(sqlite3_column_int(s, 3)), target: string(s, 4), system: system,
                                 managed: reason == 6))
        }
        return entries
    }

    static func reset(_ entry: ApplicationPermission,
                      run: (String, [String]) -> SystemTools.Output = {
                          let output = MaintenanceCommandRunner.run(.init($0, $1, timeout: 15))
                          return .init(status: output.ok ? 0 : -1, stdout: "", stderr: output.text)
                      }) throws {
        guard entry.canReset else { throw failure("Cette autorisation doit être gérée dans les Réglages Système.") }
        let service = String(entry.service.dropFirst("kTCCService".count))
        let output = run("/usr/bin/tccutil", ["reset", service, entry.client])
        guard output.ok else { throw failure("macOS a refusé la réinitialisation. Utilisez les Réglages Système. \(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines))") }
    }

    private static func rows(_ db: OpaquePointer, sql: String, visit: (OpaquePointer) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw failure("La lecture des autorisations a échoué.")
        }
        defer { sqlite3_finalize(statement) }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW { visit(statement); status = sqlite3_step(statement) }
        guard status == SQLITE_DONE else { throw failure("La lecture des autorisations est incomplète. Réessayez.") }
    }
    private static func string(_ s: OpaquePointer, _ index: Int32) -> String {
        sqlite3_column_text(s, index).map { String(cString: $0) } ?? ""
    }
    private static func failure(_ text: String) -> NSError { NSError(domain: "MacCare.ApplicationPermissions", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
