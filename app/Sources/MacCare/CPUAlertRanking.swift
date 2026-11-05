import Foundation

enum CPUAlertRanking {
    static func candidates(_ processes: [TrayProcess], applications: [MemoryAlertApplication]) -> [MemoryAlertCandidate] {
        let apps = Dictionary(applications.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        return processes.compactMap { process -> MemoryAlertCandidate? in
            guard let value = process.cpuPercent, value.isFinite, value >= 50,
                  let app = apps[process.id.pid], MemoryAlertCandidate.isEligible(process: process, application: app) else { return nil }
            return .init(process: process, application: app)
        }.sorted {
            let a = $0.process.cpuPercent ?? 0, b = $1.process.cpuPercent ?? 0
            return a == b ? $0.id.pid < $1.id.pid : a > b
        }.prefix(3).map { $0 }
    }
}
