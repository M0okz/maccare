import Foundation

struct MemoryAlertCandidate: Identifiable {
    let process: TrayProcess
    let application: MemoryAlertApplication
    var id: TrayProcess.Identity { process.id }
    var name: String { application.name }
    var memoryText: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "\(formatter.string(from: NSNumber(value: Double(process.memory) / 1_000_000_000)) ?? "—") Go"
    }

    static func ranked(processes: [TrayProcess], applications: [MemoryAlertApplication]) -> [Self] {
        let apps = Dictionary(applications.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        return processes.compactMap { process -> Self? in
            guard process.memory >= 512_000_000, let application = apps[process.id.pid],
                  isEligible(process: process, application: application) else { return nil }
            return Self(process: process, application: application)
        }.sorted {
            $0.process.memory == $1.process.memory ? $0.id.pid < $1.id.pid : $0.process.memory > $1.process.memory
        }.prefix(3).map { $0 }
    }

    static func isEligible(process: TrayProcess, application: MemoryAlertApplication) -> Bool {
        process.canQuit && application.pid == process.id.pid && application.isRegular
            && application.bundleID != "org.maccare.app" && !application.bundlePath.hasPrefix("/System/")
            && !application.bundlePath.isEmpty && process.executable == application.executable
            && process.executable.hasPrefix(application.bundlePath + "/")
    }

    func matches(live: TrayProcess, application: MemoryAlertApplication) -> Bool {
        live.id == id && live.userID == process.userID && live.executable == process.executable
            && application.bundleID == self.application.bundleID
            && application.bundlePath == self.application.bundlePath
            && Self.isEligible(process: live, application: application)
    }
}
