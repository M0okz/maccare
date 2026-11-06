import AppKit
import Darwin

struct TrayProcess: Identifiable, Sendable, Equatable {
    struct Identity: Hashable, Sendable {
        let pid: pid_t
        let startedSeconds: UInt64
        let startedMicroseconds: UInt64
    }
    let id: Identity
    let name: String
    let userID: uid_t
    let memory: UInt64
    let cpuPercent: Double?
    let executable: String
    var energyWatts: Double? = nil

    var canQuit: Bool {
        id.pid > 1 && id.pid != getpid() && userID == getuid()
            && !executable.isEmpty && !executable.hasPrefix("/System/") && !executable.hasPrefix("/usr/libexec/")
            && !["loginwindow", "WindowServer", "launchd", "kernel_task"].contains(name)
    }
}

actor TrayProcessSampler {
    private var previous: [TrayProcess.Identity: (cpu: UInt64, energy: UInt64?, time: TimeInterval)] = [:]

    func sample(includeEnergy: Bool = false) -> [TrayProcess] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 128)
        let bytes = Int32(pids.count * MemoryLayout<pid_t>.stride)
        let copied = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, bytes) }
        guard copied > 0 else { return [] }
        var next: [TrayProcess.Identity: (cpu: UInt64, energy: UInt64?, time: TimeInterval)] = [:]
        let now = ProcessInfo.processInfo.systemUptime
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let nanosecondsPerTick = Double(timebase.numer) / Double(max(timebase.denom, 1))
        var result: [TrayProcess] = []
        for pid in pids.prefix(Int(copied)) where pid > 0 {
            guard let info = Self.info(pid) else { continue }
            let identity = Self.identity(pid, info)
            let cpu = info.ptinfo.pti_total_user + info.ptinfo.pti_total_system
            let prior = previous[identity]
            let percent = Self.cpuLoad(current: cpu, previous: prior?.cpu, seconds: prior.map { now - $0.time }, nanosecondsPerTick: nanosecondsPerTick)
            var nameBytes = [CChar](repeating: 0, count: 1024)
            let nameLength = proc_name(pid, &nameBytes, UInt32(nameBytes.count))
            let name = nameLength > 0 ? String(cString: nameBytes) : "Processus \(pid)"
            var pathBytes = [CChar](repeating: 0, count: 4096)
            let pathLength = proc_pidpath(pid, &pathBytes, UInt32(pathBytes.count))
            let path = pathLength > 0 ? String(cString: pathBytes) : ""
            // Empreinte physique, qui prend en compte la mémoire compressée du processus.
            var footprint: UInt64?
            var energy: UInt64?
            if includeEnergy {
                var usage = rusage_info_v6()
                let status = withUnsafeMutablePointer(to: &usage) { pointer in
                    pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                        proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                    }
                }
                if status == 0 { footprint = usage.ri_phys_footprint; energy = usage.ri_energy_nj }
            }
            if footprint == nil {
                var usage = rusage_info_v2()
                let status = withUnsafeMutablePointer(to: &usage) { pointer in
                    pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                        proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                    }
                }
                if status == 0 { footprint = usage.ri_phys_footprint }
            }
            guard let footprint else { continue }
            let old = previous[identity]
            let watts = Self.power(current: energy, previous: old?.energy, seconds: old.map { now - $0.time })
            next[identity] = (cpu, energy, now)
            result.append(.init(id: identity, name: name, userID: info.pbsd.pbi_uid,
                                memory: footprint, cpuPercent: percent, executable: path, energyWatts: watts))
        }
        previous = next
        return result
    }

    /// Les compteurs proc_taskinfo suivent la base de temps Mach de l’hôte.
    static func cpuLoad(current: UInt64, previous: UInt64?, seconds: TimeInterval?, nanosecondsPerTick: Double) -> Double? {
        guard let previous, let seconds, seconds.isFinite, seconds > 0, seconds <= 10, current >= previous else { return nil }
        guard nanosecondsPerTick.isFinite, nanosecondsPerTick > 0 else { return nil }
        return Double(current - previous) * nanosecondsPerTick / 1_000_000_000 / seconds * 100
    }

    static func power(current: UInt64?, previous: UInt64?, seconds: TimeInterval?) -> Double? {
        guard let current, let previous, let seconds, seconds.isFinite, seconds > 0, seconds <= 10, current >= previous else { return nil }
        let watts = Double(current - previous) / 1_000_000_000 / seconds
        return watts.isFinite ? watts : nil
    }

    static func info(_ pid: pid_t) -> proc_taskallinfo? {
        var info = proc_taskallinfo()
        let size = Int32(MemoryLayout<proc_taskallinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, size) == size else { return nil }
        return info
    }

    static func identity(_ pid: pid_t, _ info: proc_taskallinfo) -> TrayProcess.Identity {
        .init(pid: pid, startedSeconds: info.pbsd.pbi_start_tvsec, startedMicroseconds: info.pbsd.pbi_start_tvusec)
    }
}

@MainActor
final class TrayProcessController: ObservableObject {
    struct Presentation {
        let name: String
        let icon: NSImage?
    }
    @Published private(set) var processes: [TrayProcess] = []
    @Published private(set) var pending: Set<TrayProcess.Identity> = []
    @Published private(set) var message: String?
    private let sampler = TrayProcessSampler()
    private var presentations: [TrayProcess.Identity: Presentation] = [:]

    func monitor() async {
        while !Task.isCancelled {
            let snapshot = await sampler.sample()
            guard !Task.isCancelled else { return }
            record(snapshot)
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
    }

    func record(_ snapshot: [TrayProcess]) {
        processes = snapshot
        let alive = Set(snapshot.map(\.id))
        let completed = pending.subtracting(alive)
        if !completed.isEmpty { message = "Processus fermé." }
        pending.formIntersection(alive)
        presentations = presentations.filter { alive.contains($0.key) }
    }

    /// Icône et nom passent par des appels système synchrones : une seule lecture par processus.
    func presentation(for process: TrayProcess) -> Presentation {
        if let known = presentations[process.id] { return known }
        let app = NSRunningApplication(processIdentifier: process.id.pid)
        let presentation = Presentation(name: app?.localizedName ?? process.name, icon: app?.icon)
        presentations[process.id] = presentation
        return presentation
    }

    /// Revérifie l’identité (PID + date de démarrage) et le propriétaire avant toute action.
    func quit(_ process: TrayProcess, force: Bool = false) {
        guard process.canQuit else { message = "Ce processus ne peut pas être quitté depuis MacCare."; return }
        guard let live = TrayProcessSampler.info(process.id.pid),
              TrayProcessSampler.identity(process.id.pid, live) == process.id else {
            message = "Ce processus s’est déjà fermé ou a été remplacé."; return
        }
        guard live.pbsd.pbi_uid == getuid() else { message = "Le propriétaire du processus a changé."; return }
        let requested: Bool
        if let app = NSRunningApplication(processIdentifier: process.id.pid) {
            requested = force ? app.forceTerminate() : app.terminate()
        } else {
            requested = kill(process.id.pid, force ? SIGKILL : SIGTERM) == 0
        }
        if requested {
            pending.insert(process.id)
            message = force ? "Arrêt forcé demandé à \(process.name)." :
                "Fermeture demandée à \(process.name). Une app peut demander d’enregistrer vos documents."
        } else {
            message = "Impossible de demander la fermeture de \(process.name). Le processus peut être protégé ou déjà fermé."
        }
    }
}
