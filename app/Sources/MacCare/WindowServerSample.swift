import Darwin
import Foundation

/// Les outils macOS permettent de lire le temps CPU et l’empreinte de ce processus protégé.
struct WindowServerSample {
    let id: TrayProcess.Identity
    let userID: uid_t
    let cpuSeconds: TimeInterval?
    let timestamp: TimeInterval

    struct Counters {
        let bytes: UInt64?
        let idleWakeups: UInt64?
        let timestamp: TimeInterval
    }
    var counters: Counters? = nil

    static func read(previous: Self?, sampleWakeups: Bool) -> Self? {
        var entry = passwd(), user: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16384)
        guard getpwnam_r("_windowserver", &entry, &buffer, buffer.count, &user) == 0, user != nil else { return nil }
        let uid = entry.pw_uid
        let kind = UInt32(PROC_UID_ONLY)
        let size = proc_listpids(kind, uid, nil, 0)
        guard size > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(size) / MemoryLayout<pid_t>.stride + 16)
        let bytes = pids.withUnsafeMutableBytes { proc_listpids(kind, uid, $0.baseAddress, Int32($0.count)) }
        guard bytes > 0 else { return nil }
        for pid in pids.prefix(Int(bytes) / MemoryLayout<pid_t>.stride) where pid > 0 {
            guard let id = identity(pid, uid: uid) else { continue }
            // L’accueil relève IDLEW en même temps que la mémoire. Le volet, plus
            // fréquent, peut réutiliser la mémoire sans calculer de score énergétique.
            let now = ProcessInfo.processInfo.systemUptime
            let counters: Counters
            if !sampleWakeups, previous?.id == id, let cached = previous?.counters, now - cached.timestamp < 30 {
                counters = cached
            } else {
                let output = SystemTools.run("/usr/bin/top", ["-l", "1", "-F", "-R", "-c", "e", "-pid", String(pid),
                                                              "-n", "1", "-stats", "pid,mem,idlew"], environment: ["LC_ALL": "C"])
                counters = Self.counters(in: output.ok ? output.stdout : "", pid: pid,
                                         timestamp: ProcessInfo.processInfo.systemUptime)
            }
            let cpu = SystemTools.run("/bin/ps", ["-p", String(pid), "-o", "time="], environment: ["LC_ALL": "C"])
            let timestamp = ProcessInfo.processInfo.systemUptime
            guard identity(pid, uid: uid) == id else { continue }
            return Self(id: id, userID: uid, cpuSeconds: cpu.ok ? seconds(cpu.stdout) : nil,
                        timestamp: timestamp, counters: counters)
        }
        return nil
    }

    private static func identity(_ pid: pid_t, uid: uid_t) -> TrayProcess.Identity? {
        var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.size
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size == MemoryLayout<kinfo_proc>.size,
              info.kp_proc.p_pid == pid, info.kp_eproc.e_ucred.cr_uid == uid else { return nil }
        let name = withUnsafeBytes(of: info.kp_proc.p_comm) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
        guard name == "WindowServer" else { return nil }
        let start = info.kp_proc.p_starttime
        return .init(pid: pid, startedSeconds: UInt64(start.tv_sec), startedMicroseconds: UInt64(start.tv_usec))
    }

    static func counters(in output: String, pid: pid_t, timestamp: TimeInterval) -> Counters {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 3, Int32(fields[0]) == pid else { continue }
            return Counters(bytes: bytes(fields[1]), idleWakeups: UInt64(fields[2]), timestamp: timestamp)
        }
        return Counters(bytes: nil, idleWakeups: nil, timestamp: timestamp)
    }

    private static func bytes(_ value: Substring) -> UInt64? {
        // top utilise les multiples binaires de humanize_number pour la colonne MEM.
        let units: [Character] = ["B", "K", "M", "G", "T"]
        guard let unit = value.last, let exponent = units.firstIndex(of: unit),
              let amount = Double(value.dropLast()), amount.isFinite, amount >= 0 else { return nil }
        return UInt64(exactly: (amount * Double(UInt64(1) << (10 * exponent))).rounded())
    }

    static func seconds(_ text: String) -> TimeInterval? {
        let fields = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ":")
        guard (2...3).contains(fields.count), let last = fields.last, let seconds = Double(last),
              seconds.isFinite, (0..<60).contains(seconds) else { return nil }
        var minutes = 0.0
        for field in fields.dropLast() {
            guard let value = UInt(field) else { return nil }
            minutes = minutes * 60 + Double(value)
        }
        return minutes * 60 + seconds
    }

    func process(after previous: Self?, maximumInterval: TimeInterval) -> TrayProcess {
        var percent: Double?
        if let previous, id == previous.id, let cpuSeconds, let prior = previous.cpuSeconds {
            let interval = timestamp - previous.timestamp
            if interval > 0, interval <= maximumInterval, cpuSeconds >= prior {
                percent = (cpuSeconds - prior) / interval * 100
            }
        }
        var wakeRate: Double?
        if let previous, previous.id == id, let counters, let prior = previous.counters {
            wakeRate = TrayProcessSampler.rate(current: counters.idleWakeups, previous: prior.idleWakeups,
                                               seconds: counters.timestamp - prior.timestamp, maximumInterval: maximumInterval)
        }
        return .init(id: id, name: "WindowServer", userID: userID, memory: counters?.bytes, cpuPercent: percent,
                     executable: "", idleWakeupsPerSecond: wakeRate)
    }
}
