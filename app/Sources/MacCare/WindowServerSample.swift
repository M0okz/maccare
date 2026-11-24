import Darwin
import Foundation

/// WindowServer autorise la lecture de son identité BSD et de son temps CPU via ps.
struct WindowServerSample {
    let id: TrayProcess.Identity
    let userID: uid_t
    let cpuSeconds: TimeInterval?
    let timestamp: TimeInterval

    static func read() -> Self? {
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
            let output = SystemTools.run("/bin/ps", ["-p", String(pid), "-o", "time="], environment: ["LC_ALL": "C"])
            let now = ProcessInfo.processInfo.systemUptime
            guard identity(pid, uid: uid) == id else { continue }
            return Self(id: id, userID: uid, cpuSeconds: output.ok ? seconds(output.stdout) : nil, timestamp: now)
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
        return .init(id: id, name: "WindowServer", userID: userID, memory: nil, cpuPercent: percent, executable: "")
    }
}
