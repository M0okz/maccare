import AppKit
import Combine
import MacCareBattery
import ServiceManagement

@MainActor
final class BatteryModel: ObservableObject {
    @Published private(set) var snapshot: BatterySnapshot?
    @Published private(set) var protection: BatteryProtectionStatus?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var helperEnabled = false
    @Published private(set) var requiresApproval = false
    @Published var configuration: BatteryConfiguration
    private let client: any BatteryClient
    private let defaults: UserDefaults
    private let sessionID = UUID()
    private var wakeSubscription: AnyCancellable?
    @Published private(set) var isTerminating = false
    private var commandInFlight = false
    private var commandWaiters: [CheckedContinuation<Void, Never>] = []
    private var mayOwnLease = false
    private var ownsLease = false
    private var nextHelperStatus = Date.distantPast
    private var monitoring: Task<Void, Never>?
    private static let preferencesKey = "battery.configuration"

    init(defaults: UserDefaults = .standard, monitor: Bool = true, client: (any BatteryClient)? = nil) {
        self.client = client ?? SystemBatteryClient()
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.preferencesKey),
           let value = try? JSONDecoder().decode(BatteryConfiguration.self, from: data), value.isValid {
            configuration = value
        } else { configuration = .init() }
        if monitor {
            wakeSubscription = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
                .sink { [weak self] _ in Task { @MainActor in await self?.refresh(force: true) } }
            monitoring = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refresh()
                    do { try await Task.sleep(for: .seconds(15)) } catch { break }
                }
            }
        }
    }
    deinit { monitoring?.cancel() }

    var active: Bool { protection?.active == true }
    var supported: Bool { protection?.supported == true }
    var restoring: Bool { protection?.restoring == true }
    var recoveryReady: Bool { protection?.recoveryReady == true }
    var pendingChanges: Bool { active && protection?.configuration != configuration }
    var nativeControl: Bool { protection?.capabilities?.backend == .nativeLimit }
    var supportsThermalProtection: Bool {
        protection?.capabilities?.supportsThermalProtection ?? (protection?.firmwareManaged != true)
    }
    var availableLimits: [Int] {
        if let capabilities = protection?.capabilities, capabilities.isValid { return capabilities.supportedLimits }
        return Array(stride(from: 50, through: 100, by: 5))
    }
    var message: String {
        if !helperEnabled { return "Suivi de la batterie · assistant requis pour la protection" }
        return protection?.message ?? "Vérification du contrôle de charge…"
    }

    func refresh(force: Bool = false) async {
        guard !busy, !isTerminating else { return }
        busy = true
        defer { busy = false }
        helperEnabled = client.status == .enabled
        requiresApproval = client.status == .requiresApproval
        snapshot = await client.snapshot()
        guard helperEnabled else { protection = nil; ownsLease = false; return }
        guard force || ownsLease || protection == nil || Date() >= nextHelperStatus else { return }
        nextHelperStatus = Date().addingTimeInterval(60)
        do {
            let result = try await client.request(ownsLease ? .heartbeat : .status, configuration: nil, sessionID: sessionID)
            accept(result)
        } catch {
            self.error = error.localizedDescription
            // Never display a cached "active" after losing the helper connection.
            protection = nil; ownsLease = false
        }
    }

    func perform(_ command: BatteryCommand) async {
        guard !busy, !isTerminating else { return }
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
        do {
            if client.status == .requiresApproval { client.openApproval() }
            else { try client.register() }
        } catch { self.error = error.localizedDescription }
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
        if !status.active, let capabilities = status.capabilities, capabilities.isValid,
           !capabilities.supportedLimits.contains(configuration.limit),
           let limit = capabilities.supportedLimits.min(by: { abs($0 - configuration.limit) < abs($1 - configuration.limit) }) {
            configuration.limit = limit
        }
        if !status.active || status.restoring || !status.ownedByCaller { ownsLease = false }
        if !status.active && !status.restoring { mayOwnLease = false }
    }
}
