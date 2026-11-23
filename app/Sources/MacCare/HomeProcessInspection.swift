import Darwin
import Foundation

struct HomeProcessInspection: Sendable {
    let parent: String?
    let threads: Int
    let files: Int?
    let directory: String?
    let diskRead: UInt64?
    let diskWritten: UInt64?
    let user: String
    let service: String?
    let reason: String?

    /// Les lectures détaillées ne concernent que le PID consulté dans la fiche.
    static func read(_ process: TrayProcess) -> Self? {
        let pid = process.id.pid
        func current() -> proc_taskallinfo? {
            guard let info = TrayProcessSampler.info(pid), TrayProcessSampler.identity(pid, info) == process.id else { return nil }
            return info
        }
        guard let info = current() else { return nil }
        let ppid = pid_t(info.pbsd.pbi_ppid)
        var parent: String? = ppid == 1 ? "launchd · 1" : nil
        if ppid > 0, let pinfo = TrayProcessSampler.info(ppid),
           pinfo.pbsd.pbi_start_tvsec <= process.id.startedSeconds {
            var name = [CChar](repeating: 0, count: 1024)
            parent = proc_name(ppid, &name, UInt32(name.count)) > 0 ? "\(String(cString: name)) · \(ppid)" : "PID \(ppid)"
        }

        var paths = proc_vnodepathinfo()
        let pathSize = Int32(MemoryLayout.size(ofValue: paths))
        var directory: String?
        if proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &paths, pathSize) == pathSize {
            directory = withUnsafeBytes(of: &paths.pvi_cdir.vip_path) { bytes in
                String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
        }

        var usage = rusage_info_v2()
        let hasUsage = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) == 0 }
        }
        let expected = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        var files: Int?
        if expected > 0 {
            let stride = MemoryLayout<proc_fdinfo>.stride
            var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(expected) / stride + 32)
            let copied = descriptors.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
            if copied > 0 { files = Int(copied) / stride }
        }
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16384)
        let user = buffer.withUnsafeMutableBufferPointer { bytes -> String in
            let status = getpwuid_r(process.userID, &entry, bytes.baseAddress, bytes.count, &result)
            return status == 0 && result != nil ? String(cString: entry.pw_name) : "UID \(process.userID)"
        }
        var service: String?
        var reason: String?
        if ppid == 1, process.userID == getuid() {
            let jobs = SystemTools.run("/bin/launchctl", ["list"])
            if jobs.ok {
                for line in jobs.stdout.split(separator: "\n") {
                    let columns = line.split(separator: "\t", maxSplits: 2)
                    guard columns.count == 3, Int32(columns[0]) == pid else { continue }
                    service = String(columns[2])
                    let why = SystemTools.run("/bin/launchctl", ["blame", "gui/\(process.userID)/\(columns[2])"])
                    let text = why.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    if why.ok && !text.isEmpty { reason = text }
                    break
                }
            }
        }
        guard current() != nil else { return nil }
        return Self(parent: parent, threads: Int(info.ptinfo.pti_threadnum), files: files, directory: directory,
                    diskRead: hasUsage ? usage.ri_diskio_bytesread : nil, diskWritten: hasUsage ? usage.ri_diskio_byteswritten : nil,
                    user: user, service: service, reason: reason)
    }
}
