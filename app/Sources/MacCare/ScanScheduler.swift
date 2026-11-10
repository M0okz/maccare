import AppKit
import CoreServices
import IOKit.ps
import ServiceManagement
import UserNotifications

/// Fréquence de l'analyse planifiée.
enum ScanFrequency: String, CaseIterable, Identifiable {
    case off, daily, weekly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Jamais"
        case .daily: return "Chaque jour"
        case .weekly: return "Chaque semaine"
        }
    }
    var interval: TimeInterval? {
        switch self {
        case .off: return nil
        case .daily: return 86_400
        case .weekly: return 7 * 86_400
        }
    }
}

/// Analyse planifiée : lance un Smart Scan **en analyse seule** quand le dernier scan complet est
/// plus ancien que la fréquence choisie, puis notifie le total. **Ne supprime jamais rien.**
///
/// Pour ne pas déranger, jamais :
/// - avant la fin du parcours de bienvenue, ni sans Accès complet au disque (sans lui, lire les
///   données d'autres apps pourrait faire surgir une invite macOS en arrière-plan) ;
/// - quand MacCare est au premier plan (on n'efface pas une revue en cours), ni pendant un scan ou
///   un nettoyage ;
/// - en économie d'énergie, sur batterie faible, ou si le Mac chauffe (un scan planifié en cours
///   est alors arrêté).
/// Une échéance manquée (veille, app fermée) ne donne lieu qu'à **un** scan. Ne tourne que tant que
/// l'app est ouverte (fenêtre ou barre des menus) ; voir « Ouvrir à la connexion ».
@MainActor
final class ScanScheduler: ObservableObject {
    static let frequencyKey = "scheduledScanFrequency"
    /// Délai entre deux vérifications, et avant la première après le lancement.
    private static let checkEvery: TimeInterval = 30 * 60
    private static let firstCheckAfter: TimeInterval = 60

    private let smart: SmartScanModel
    private let notifications = NotificationRouter()
    private var timer: Timer?
    /// Vrai pendant un scan lancé par le planificateur (lui seul déclenche une notification).
    private var scheduledRunning = false
    /// Vrai entre la décision de lancer et le lancement effectif (vérification des autorisations).
    private var starting = false

    /// Désactivée tant que l'utilisateur ne l'a pas choisie (clé absente = jamais).
    static let defaultFrequency = ScanFrequency.off

    static var frequency: ScanFrequency {
        ScanFrequency(rawValue: UserDefaults.standard.string(forKey: frequencyKey) ?? "") ?? defaultFrequency
    }

    /// Demande l'autorisation de notifier. Uniquement en réponse à un geste de l'utilisateur
    /// (activation de la planification dans les Réglages), jamais en arrière-plan.
    static func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert]) { granted, _ in
                    DispatchQueue.main.async { completion(granted) }
                }
            } else {
                let ok = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
                DispatchQueue.main.async { completion(ok) }
            }
        }
    }

    private var observers: [NSObjectProtocol] = []

    init(smart: SmartScanModel, onOpen: @escaping () -> Void) {
        self.smart = smart
        notifications.onOpen = onOpen
        UNUserNotificationCenter.current().delegate = notifications
        smart.onComplete = { [weak self] safe, _ in self?.completed(safe: safe) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstCheckAfter) { [weak self] in self?.check() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkEvery, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        // Rattrapage au réveil (une seule vérification, après que le système s'est stabilisé).
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstCheckAfter) { self?.check() }
        })
        // Le Mac chauffe : un scan planifié en cours s'arrête.
        observers.append(NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.scheduledRunning, Self.tooHot else { return }
                self.smart.cancelScan()
            }
        })
    }

    private static var tooHot: Bool {
        let t = ProcessInfo.processInfo.thermalState
        return t == .serious || t == .critical
    }

    /// Vrai sur batterie avec moins de 20 % de charge.
    private static var lowBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                  let cap = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            if cap * 100 / max < 20 { return true }
        }
        return false
    }

    /// Vrai si la fenêtre principale est affichée : l'utilisateur peut être en train de revoir des
    /// résultats, qu'un scan planifié ne doit pas remplacer.
    private var mainWindowVisible: Bool {
        NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
    }

    /// Vrai si le moment s'y prête (hors autorisations, vérifiées à part).
    private var quietMoment: Bool {
        !NSApp.isActive
            && (smart.stage == .idle || (smart.stage == .results && !mainWindowVisible))
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
            && !Self.tooHot
            && !Self.lowBattery
    }

    /// Lance le scan s'il est dû et si le moment s'y prête. Une seule fois par échéance : le scan
    /// complet met à jour la date du dernier scan.
    func check() {
        guard !starting, !ScanPreferences.currentCategories.isEmpty else { return }
        if smart.stage != .scanning { scheduledRunning = false } // scan précédent annulé ou en échec
        guard let interval = Self.frequency.interval,
              UserDefaults.standard.bool(forKey: "firstRunCompleted") else { return }
        let last = smart.lastCompletedAt ?? .distantPast
        guard Date().timeIntervalSince(last) >= interval, quietMoment, !scheduledRunning else { return }
        starting = true // pas de second départ pendant la vérification
        Task.detached(priority: .utility) {
            // Vérification sans invite : sans Accès complet au disque, on ne scanne pas en arrière-plan.
            let fullDisk = FullDiskAccess.isGranted()
            await MainActor.run {
                self.starting = false
                guard fullDisk, self.quietMoment else { return }
                self.scheduledRunning = true
                self.smart.scan()
            }
        }
    }

    private func completed(safe: UInt64) {
        guard scheduledRunning else { return }
        scheduledRunning = false
        notify(safe: safe)
    }

    /// Notifie le résultat, si l'utilisateur l'a autorisé. Ne demande **jamais** l'autorisation
    /// (voir `requestNotificationPermission`, appelée depuis les Réglages).
    private func notify(safe: UInt64) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Analyse MacCare terminée"
        content.body = safe > 0
            ? "\(humanSize(safe)) récupérables en toute sûreté. Rien n'a été supprimé : ouvrez MacCare pour décider."
            : "Rien à récupérer pour l'instant."
        let request = UNNotificationRequest(identifier: "maccare.scheduled-scan", content: content, trigger: nil)
        center.getNotificationSettings { settings in
            // Sans autorisation, le résultat reste visible dans l'app et la barre des menus.
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                center.add(request)
            }
        }
    }
}

/// Ouverture de MacCare à la connexion, via l'API d'Apple (`SMAppService`). Désactivée par défaut.
enum LoginLaunch {
    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled }
    /// macOS demande parfois une approbation dans Réglages > Général > Ouverture.
    static var needsApproval: Bool { status == .requiresApproval }

    static func set(_ enabled: Bool) throws {
        if enabled {
            guard !AppInstallLocation.isTemporary else { throw HelperClient.HelperError.temporaryLocation }
            try SMAppService.mainApp.register()
        } else { try SMAppService.mainApp.unregister() }
    }

    /// Read while the launch event is current, in `applicationWillFinishLaunching`.
    @MainActor private static func launchEventIsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == kCoreEventClass, event.eventID == kAEOpenApplication,
              let kind = event.paramDescriptor(forKeyword: keyAEPropData) else { return false }
        return kind.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// Seconds since this user's console session began, from the system login records.
    private static func sessionAge(now: Date = .now) -> TimeInterval? {
        var latest: TimeInterval?
        setutxent(); defer { endutxent() }
        while let entry = getutxent() {
            guard entry.pointee.ut_type == USER_PROCESS else { continue }
            let (user, line) = withUnsafePointer(to: entry.pointee) { pointer in
                (withUnsafeBytes(of: pointer.pointee.ut_user) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) },
                 withUnsafeBytes(of: pointer.pointee.ut_line) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) })
            }
            guard user == NSUserName(), line == "console" else { continue }
            let started = TimeInterval(entry.pointee.ut_tv.tv_sec)
            latest = max(latest ?? started, started)
        }
        return latest.map { now.timeIntervalSince1970 - $0 }
    }

    @MainActor static func launchedAtLogin() -> Bool {
        launchedAtLogin(itemEnabled: isEnabled, launchEvent: launchEventIsLoginItem(), sessionAge: sessionAge())
    }

    /// macOS does not always mark a login launch. With the item enabled, a launch just after the
    /// session starts is that launch: an app opened later finds this one already running.
    static func launchedAtLogin(itemEnabled: Bool, launchEvent: Bool, sessionAge: TimeInterval?) -> Bool {
        guard itemEnabled else { return false }
        if launchEvent { return true }
        guard let sessionAge else { return false }
        return (0...180).contains(sessionAge)
    }

    /// Without the menu bar or a finished first run, a closed window would leave MacCare unreachable.
    static func startsWithoutWindow(launchedAtLogin: Bool, menuBarEnabled: Bool, firstRunCompleted: Bool) -> Bool {
        launchedAtLogin && menuBarEnabled && firstRunCompleted
    }
}

/// Espace libre du disque de démarrage (capacité disponible pour un usage important, comme le Finder).
enum DiskSpace {
    static func current() -> (free: UInt64, total: UInt64)? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let free = v.volumeAvailableCapacityForImportantUsage, let total = v.volumeTotalCapacity else { return nil }
        return (UInt64(max(0, free)), UInt64(max(0, total)))
    }
}
