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

    var canQuit: Bool {
        id.pid > 1 && id.pid != getpid() && userID == getuid()
            && !executable.isEmpty && !executable.hasPrefix("/System/") && !executable.hasPrefix("/usr/libexec/")
            && !["loginwindow", "WindowServer", "launchd", "kernel_task"].contains(name)
    }
}

actor TrayProcessSampler {
    private var previous: [TrayProcess.Identity: (cpu: UInt64, time: TimeInterval)] = [:]

    func sample() -> [TrayProcess] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 128)
        let bytes = Int32(pids.count * MemoryLayout<pid_t>.stride)
        let copied = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, bytes) }
        guard copied > 0 else { return [] }
        var next: [TrayProcess.Identity: (cpu: UInt64, time: TimeInterval)] = [:]
        let now = ProcessInfo.processInfo.systemUptime
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let nanosecondsPerTick = Double(timebase.numer) / Double(max(timebase.denom, 1))
        var result: [TrayProcess] = []
        for pid in pids.prefix(Int(copied)) where pid > 0 {
            guard let info = Self.info(pid) else { continue }
            let identity = Self.identity(pid, info)
            let cpu = info.ptinfo.pti_total_user + info.ptinfo.pti_total_system
            var percent: Double?
            if let old = previous[identity], now > old.time, cpu >= old.cpu {
                percent = Double(cpu - old.cpu) * nanosecondsPerTick / 1_000_000_000 / (now - old.time) * 100
            }
            next[identity] = (cpu, now)
            var nameBytes = [CChar](repeating: 0, count: 1024)
            let nameLength = proc_name(pid, &nameBytes, UInt32(nameBytes.count))
            let name = nameLength > 0 ? String(cString: nameBytes) : "Processus \(pid)"
            var pathBytes = [CChar](repeating: 0, count: 4096)
            let pathLength = proc_pidpath(pid, &pathBytes, UInt32(pathBytes.count))
            let path = pathLength > 0 ? String(cString: pathBytes) : ""
            // Empreinte physique, qui prend en compte la mémoire compressée du processus.
            var usage = rusage_info_v2()
            let status = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard status == 0 else { continue }
            result.append(.init(id: identity, name: name, userID: info.pbsd.pbi_uid,
                                memory: usage.ri_phys_footprint, cpuPercent: percent, executable: path))
        }
        previous = next
        return result
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
    @Published private(set) var processes: [TrayProcess] = []
    @Published private(set) var pending: Set<TrayProcess.Identity> = []
    @Published private(set) var message: String?
    private let sampler = TrayProcessSampler()

    func monitor() async {
        while !Task.isCancelled {
            let snapshot = await sampler.sample()
            guard !Task.isCancelled else { return }
            processes = snapshot
            let alive = Set(snapshot.map(\.id))
            let completed = pending.subtracting(alive)
            if !completed.isEmpty { message = "Processus fermé." }
            pending.formIntersection(alive)
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
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
