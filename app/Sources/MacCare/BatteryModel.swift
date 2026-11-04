import AppKit
import Combine
import MacCareBattery
import MacCareHelperProtocol
import ServiceManagement

@MainActor
final class BatteryModel: ObservableObject {
    @Published private(set) var snapshot: BatterySnapshot?
    @Published private(set) var protection: BatteryProtectionStatus?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var helperEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var loadedHelperProtocol: Int?
    @Published var configuration: BatteryConfiguration
    @Published private(set) var profiles = BatteryProfile.presets
    @Published private(set) var schedules: [BatterySchedule] = []
    @Published private(set) var history: [BatteryHistoryEntry] = []
    @Published private(set) var automationEvents: [String] = []
    @Published private(set) var automationsLoaded = false
    @Published private(set) var automating = false
    @Published private(set) var historyError: String?
    var openSection: (() -> Void)?
    private let historyStore: BatteryHistoryStore
    private let client: any BatteryClient
    private let defaults: UserDefaults
    private let sessionID = UUID()
    private var wakeSubscription: AnyCancellable?
    @Published private(set) var isTerminating = false
    private var commandInFlight = false
    private var commandWaiters: [CheckedContinuation<Void, Never>] = []
    private var mayOwnLease = false
    private var ownsLease = false
    private var renewAfterLostReply = false
    private var nextHelperStatus = Date.distantPast
    private var monitoring: Task<Void, Never>?
    private static let preferencesKey = "battery.configuration"
    /// Set while the user wants protection on. It survives quitting, which only stops the session
    /// for this run; an explicit deactivation or a safety stop removes it.
    static let resumeKey = "battery.protection.resume"
    private var resumeAttempted = false

    init(defaults: UserDefaults = .standard, monitor: Bool = true, client: (any BatteryClient)? = nil, historyStore: BatteryHistoryStore? = nil) {
        self.historyStore = historyStore ?? BatteryHistoryStore()
        self.client = client ?? SystemBatteryClient()
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.preferencesKey),
           let value = try? JSONDecoder().decode(BatteryConfiguration.self, from: data), value.isValid {
            configuration = value
        } else { configuration = .init() }
        if let data = defaults.data(forKey: "battery.profiles.v1"),
           let saved = try? JSONDecoder().decode([BatteryProfile].self, from: data), saved.count <= 50,
           saved.allSatisfy({ $0.isValid }), Set(saved.map(\.id)).count == saved.count { profiles = saved }
        automationEvents = Array((defaults.stringArray(forKey: "battery.events.v1") ?? []).prefix(100))
        if monitor {
            BatteryIntentBridge.bind(self)
            wakeSubscription = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
                .sink { [weak self] _ in Task { @MainActor in await self?.refresh(force: true) } }
            monitoring = Task { [weak self] in
                await self?.loadAdvancedData()
                while !Task.isCancelled {
                    await self?.refresh()
                    await self?.resumeProtectionIfNeeded()
                    await self?.recordHistory()
                    await self?.processSchedules()
                    do { try await Task.sleep(for: .seconds(15)) } catch { break }
                }
            }
        }
    }
    deinit { monitoring?.cancel() }

    var active: Bool { protection?.active == true }
    var supported: Bool { protection?.supported == true }
    var restoring: Bool { protection?.restoring == true }
    var restorationDeferred: Bool { protection?.deferredRestorationTarget != nil }
    var recoveryReady: Bool { protection?.recoveryReady == true }
    var pendingChanges: Bool { active && protection?.configuration != configuration }
    var nativeControl: Bool { protection?.capabilities?.backend == .nativeLimit }
    var nativePolicyControl: Bool { protection?.capabilities?.backend == .nativePolicy }
    var usesAppleChargeControl: Bool { nativeControl || nativePolicyControl }
    var helperUpdateRequired: Bool {
        helperEnabled && loadedHelperProtocol.map { $0 != HelperIdentity.protocolVersion } == true
    }
    var supportsThermalProtection: Bool {
        protection?.capabilities?.supportsThermalProtection ?? (protection?.firmwareManaged != true)
    }
    var availableLimits: [Int] {
        if let capabilities = protection?.capabilities, capabilities.isValid { return capabilities.supportedLimits }
        return Array(stride(from: 50, through: 100, by: 5))
    }
    var message: String {
        if !helperEnabled { return "Suivi de la batterie · assistant requis pour la protection" }
        if helperUpdateRequired { return "Assistant système à mettre à jour" }
        return protection?.message ?? "Vérification du contrôle de charge…"
    }

    func refresh(force: Bool = false, fromAutomation: Bool = false) async {
        guard !busy, !isTerminating, !automating || fromAutomation else { return }
        busy = true
        defer { busy = false }
        helperEnabled = client.status == .enabled
        requiresApproval = client.status == .requiresApproval
        snapshot = await client.snapshot()
        guard !isTerminating else { return }
        guard helperEnabled else { protection = nil; ownsLease = false; loadedHelperProtocol = nil; return }
        guard force || ownsLease || protection == nil || Date() >= nextHelperStatus else { return }
        nextHelperStatus = Date().addingTimeInterval(60)
        do {
            loadedHelperProtocol = try await client.loadedHelperProtocolVersion()
            guard !isTerminating else { return }
            if helperUpdateRequired {
                protection = nil; ownsLease = false
                error = "La version chargée de l’assistant doit être mise à jour avant le contrôle de la batterie."
                return
            }
            let owned = ownsLease
            let result = try await client.request(owned ? .heartbeat : .status, configuration: nil, sessionID: sessionID)
            guard !isTerminating else { return }
            accept(result)
            // A running session that ended on an error may be a safety stop, such as a lost
            // power input: the next launch must not start it again without the user.
            if owned, !result.active, result.error != nil { defaults.removeObject(forKey: Self.resumeKey) }
        } catch {
            self.error = error.localizedDescription
            if ownsLease { renewAfterLostReply = true }
            // Never display a cached "active" after losing the helper connection.
            protection = nil; ownsLease = false
        }
    }

    func perform(_ command: BatteryCommand, fromAutomation: Bool = false) async {
        guard !busy, !isTerminating, !automating || fromAutomation else { return }
        busy = true; error = nil; commandInFlight = true
        defer {
            commandInFlight = false
            let waiters = commandWaiters; commandWaiters.removeAll()
            waiters.forEach { $0.resume() }
            busy = false
            helperEnabled = client.status == .enabled
            requiresApproval = client.status == .requiresApproval
        }
        let requestedConfiguration = configuration
        if command == .disable { defaults.removeObject(forKey: Self.resumeKey); renewAfterLostReply = false }
        do {
            if command == .enable {
                try await client.prepareProtection()
                guard !isTerminating else { return }
                mayOwnLease = true
            }
            let result = try await client.request(command, configuration: command == .enable ? requestedConfiguration : nil, sessionID: sessionID)
            accept(result)
            if result.error == nil {
                if command == .enable {
                    ownsLease = result.active && result.ownedByCaller
                    defaults.set(try JSONEncoder().encode(requestedConfiguration), forKey: Self.preferencesKey)
                    if result.active { defaults.set(true, forKey: Self.resumeKey); resumeAttempted = true }
                }
                if command == .disable { ownsLease = false }
            }
        } catch {
            self.error = error.localizedDescription
            // An RPC may have executed before its reply was lost. Stop renewing the lease
            // and obtain a fresh status; do not keep an optimistic cached "active" state.
            protection = nil; ownsLease = false
        }
    }
    /// Restarts the protection the user left on, once per launch and only from a clean state.
    /// A failed attempt keeps the intent for the next launch and shows its error.
    func resumeProtectionIfNeeded() async {
        guard defaults.bool(forKey: Self.resumeKey), !resumeAttempted, !controlsBusy, helperEnabled,
              !helperUpdateRequired, let protection, protection.error == nil, supported, recoveryReady,
              !active, !restoring || restorationDeferred else { return }
        resumeAttempted = true
        await perform(.enable)
    }
    func prepareForTermination() async {
        isTerminating = true
        monitoring?.cancel()
        if commandInFlight { await withCheckedContinuation { commandWaiters.append($0) } }
        guard mayOwnLease || ownsLease || protection?.ownedByCaller == true else { return }
        ownsLease = false
        do { accept(try await client.request(.disable, configuration: nil, sessionID: sessionID)) }
        catch { self.error = error.localizedDescription }
        // If RPC/restoration fails, the independent helper keeps retrying; quitting
        // must not send another heartbeat or restart the protection.
    }
    func activateHelper() async {
        guard !busy, !isTerminating else { return }
        error = nil
        if client.status == .enabled {
            await refresh(force: true)
            return
        }
        do {
            try client.register()
        } catch {
            let failure = error as NSError
            let serviceManagementError = failure.domain == "SMAppServiceErrorDomain" ||
                failure.domain == kSMErrorDomainFramework as String
            let approvalError = failure.code == Int(kSMErrorLaunchDeniedByUser) ||
                failure.code == Int(kSMErrorAlreadyRegistered) ||
                (failure.domain == "SMAppServiceErrorDomain" && failure.code == 1)
            guard client.status == .requiresApproval, serviceManagementError, approvalError else {
                self.error = error.localizedDescription
                await refresh(force: true)
                return
            }
        }
        if client.status == .requiresApproval { client.openApproval() }
        await refresh(force: true)
    }
    /// A distinct user action replaces the loaded helper only after its old battery state is restored.
    func updateHelper() async {
        guard !busy, !isTerminating else { return }
        busy = true; error = nil
        var issue: String?
        do {
            let result = try await client.updateHelper()
            if !isTerminating, result == .requiresApproval { client.openApproval() }
        } catch { issue = error.localizedDescription }
        busy = false
        guard !isTerminating else { return }
        if let issue { error = issue; return }
        await refresh(force: true)
    }
    func openBatterySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") else { return }
        NSWorkspace.shared.open(url)
    }
    private func accept(_ status: BatteryProtectionStatus) {
        // Les assistants antérieurs ne renvoient pas les deux champs IOPS informatifs.
        // Conserver ceux du relevé local, sans modifier les données utilisées pour piloter la charge.
        var received = status.snapshot
        if received.present, received.healthState == nil { received.healthState = snapshot?.healthState }
        if received.present, received.powerStateKnown, !received.onAC, !received.charging,
           received.minutesRemaining == nil { received.minutesRemaining = snapshot?.minutesRemaining }
        snapshot = received; protection = status; error = status.error
        if !supportsThermalProtection { configuration.thermalProtection = false }
        if protection?.capabilities?.supportsSailing != true { configuration.sailingWidth = nil }
        if !status.active, let capabilities = status.capabilities, capabilities.isValid,
           !capabilities.supportedLimits.contains(configuration.limit),
           let limit = capabilities.supportedLimits.min(by: { abs($0 - configuration.limit) < abs($1 - configuration.limit) }) {
            configuration.limit = limit
        }
        if !status.active || status.restoring || !status.ownedByCaller { ownsLease = false }
        // A lost heartbeat reply must not end a confirmed session the helper still gives to this app.
        else if renewAfterLostReply { ownsLease = true }
        if !status.active || status.restoring { renewAfterLostReply = false }
        if !status.active && !status.restoring { mayOwnLease = false }
    }
}

extension BatteryModel {
    var controlsBusy: Bool { busy || automating || isTerminating }
    var supportsDischarge: Bool { protection?.capabilities?.supportsDischarge == true }
    var supportsSailing: Bool { protection?.capabilities?.supportsSailing == true }
    var cycle: BatteryCycleStatus? { protection?.cycle }

    func loadAdvancedData() async {
        guard !automationsLoaded else { return }
        do { schedules = try await historyStore.loadSchedules() }
        catch { historyError = error.localizedDescription }
        do { history = try await historyStore.load() }
        catch { historyError = error.localizedDescription }
        automationsLoaded = true
    }
    private func recordHistory() async {
        guard !isTerminating, let snapshot else { return }
        do { history = try await historyStore.append(snapshot: snapshot) }
        catch { historyError = error.localizedDescription }
    }
    func saveProfile(name: String) {
        let profile = BatteryProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), configuration: configuration)
        guard profile.isValid, profiles.count < 50, !profiles.contains(where: { $0.name.localizedCaseInsensitiveCompare(profile.name) == .orderedSame }) else {
            error = "Choisissez un nom unique de 1 à 60 caractères (50 profils maximum)."; return
        }
        profiles.append(profile); persistProfiles()
    }
    func deleteProfile(_ id: UUID) { profiles.removeAll { $0.id == id }; persistProfiles() }
    private func persistProfiles() {
        do { defaults.set(try JSONEncoder().encode(profiles), forKey: "battery.profiles.v1") }
        catch { self.error = error.localizedDescription }
    }
    func applyProfile(_ profile: BatteryProfile) async {
        do { try await executeAutomation(.configure(profile.configuration)) }
        catch { self.error = error.localizedDescription }
    }
    func saveSchedule(_ schedule: BatterySchedule) async {
        guard !controlsBusy, automationsLoaded, schedule.isValid, schedules.count < 100 || schedules.contains(where: { $0.id == schedule.id }) else { error = "Vérifiez la programmation et attendez la fin de l’action en cours."; return }
        automating = true; defer { automating = false }
        do {
            schedules = try await historyStore.upsertSchedule(schedule)
        } catch { self.error = error.localizedDescription }
    }
    func deleteSchedule(_ id: UUID) async {
        guard !controlsBusy else { return }
        automating = true; defer { automating = false }
        do {
            schedules = try await historyStore.deleteSchedule(id)
        } catch { self.error = error.localizedDescription }
    }
    func toggleSchedule(_ schedule: BatterySchedule) async {
        var next = schedule; next.enabled.toggle()
        if next.enabled && next.nextRun < .now {
            guard let date = next.occurrence(after: .now) else { error = "Cette tâche unique est terminée. Créez une nouvelle programmation."; return }
            next.nextRun = date
        }
        await saveSchedule(next)
    }
    func processSchedules(now: Date = .now) async {
        guard automationsLoaded, !controlsBusy else { return }
        do {
            let latest = try await historyStore.loadSchedules()
            guard !controlsBusy else { return }
            if latest != schedules { schedules = latest }
        } catch { historyError = error.localizedDescription; return }
        for id in schedules.map(\.id) {
            guard !Task.isCancelled, !isTerminating, !controlsBusy else { break }
            automating = true
            do {
                let result = try await historyStore.claimSchedule(id, at: now)
                schedules = result.schedules; automating = false
                guard result.claim != .notDue, let schedule = result.schedule else { continue }
                guard !isTerminating, !Task.isCancelled else { return }
                if result.claim == .missed { recordEvent("\(schedule.name) : tâche manquée, prochaine occurrence conservée.", at: now); continue }
                do {
                    try await executeAutomation(schedule.action)
                    recordEvent("\(schedule.name) : action exécutée.", at: now)
                } catch { recordEvent("\(schedule.name) : \(error.localizedDescription)", at: now) }
            } catch {
                automating = false
                self.error = "Programmation suspendue : l’état n’a pas pu être enregistré. \(error.localizedDescription)"
                return
            }
        }
    }
    func executeAutomation(_ action: BatteryAutomationAction) async throws {
        guard !controlsBusy, action.isValid else { throw AutomationError("Une action est déjà en cours ou ses réglages sont invalides.") }
        automating = true; defer { automating = false }
        openSection?()
        await refresh(force: true, fromAutomation: true)
        guard helperEnabled, recoveryReady, supported, !restoring else {
            throw AutomationError("Ouvrez Batterie et activez l’assistant système à jour avant d’utiliser cette action.")
        }
        if case .disable = action {
            await perform(.disable, fromAutomation: true)
        } else {
            guard !active || protection?.ownedByCaller == true else { throw AutomationError("La protection appartient à une autre session de MacCare.") }
            if case .configure(let value) = action {
                let profile = BatteryProfile(name: "Automatisation", configuration: value)
                if let reason = profile.unavailableReason(for: protection?.capabilities) { throw AutomationError(reason) }
                configuration = value
                await perform(.enable, fromAutomation: true)
            } else {
                guard snapshot?.onAC == true, cycle == nil else {
                    throw AutomationError("Branchez le chargeur et annulez tout cycle en cours avant cette action.")
                }
                if action == .discharge {
                    guard let percent = snapshot?.percent, percent > configuration.limit else {
                        throw AutomationError("La batterie est déjà à la limite de décharge ou en dessous.")
                    }
                }
                if action == .discharge || action == .calibrate {
                    guard snapshot?.reliableTemperature == true else { throw AutomationError("La température est inconnue ; le cycle ne peut pas démarrer.") }
                    guard supportsDischarge else { throw AutomationError("Le contrôle de l’adaptateur n’est pas disponible sur ce Mac.") }
                }
                if !active { await perform(.enable, fromAutomation: true) }
                guard error == nil, active, !isTerminating else { throw AutomationError(error ?? "La protection n’a pas démarré.") }
                switch action {
                case .topUp: await perform(.topUp, fromAutomation: true)
                case .discharge: await perform(.discharge, fromAutomation: true)
                case .calibrate: await perform(.calibrate, fromAutomation: true)
                default: break
                }
            }
        }
        if let error { throw AutomationError(error) }
    }
    private func recordEvent(_ message: String, at date: Date) {
        automationEvents.insert("\(date.formatted(date: .abbreviated, time: .shortened)) · \(message)", at: 0)
        automationEvents = Array(automationEvents.prefix(100))
        defaults.set(automationEvents, forKey: "battery.events.v1")
    }
    private struct AutomationError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
