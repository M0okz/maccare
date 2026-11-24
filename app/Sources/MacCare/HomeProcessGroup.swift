import AppKit

struct HomeProcessGroup: Identifiable {
    enum ID: Hashable {
        case application(URL, uid_t)
        case process(TrayProcess.Identity)
    }

    struct Application {
        let url: URL
        let name: String?
    }

    let id: ID
    let name: String
    let application: URL?
    let members: [TrayProcess]
    let primary: TrayProcess?
    /// Le PID de la ligne et la fiche désignent toujours le même membre au moment du clic.
    var representative: TrayProcess { primary ?? members[0] }

    let memory: UInt64?
    let cpu: Double?
    let energyScore: ProcessEnergyScore?
    var cpuLevel: ProcessCPULevel { ProcessCPULevel(cpu) }

    var cpuLabel: String { lowerBound(cpu, key: \.cpuPercent) + HomeProcessMetric.cpu(cpu) }
    var energyLabel: String { energyScore?.label ?? "—" }

    private func lowerBound(_ value: Double?, key: KeyPath<TrayProcess, Double?>) -> String {
        value != nil && members.contains { $0[keyPath: key] == nil } ? "≥ " : ""
    }

    static func collect(_ processes: [TrayProcess], registered: [pid_t: Application] = [:]) -> [Self] {
        let families = Dictionary(grouping: processes) { process -> ID in
            let registeredPath = registered[process.id.pid]?.url.path ?? ""
            let path = process.executable.isEmpty ? registeredPath : process.executable
            if path.localizedCaseInsensitiveContains(".app"),
               let owner = TrayProcessIconResolver.owningApplication(in: path) {
                return .application(owner, process.userID)
            }
            return .process(process.id)
        }
        return families.map { id, rows in
            let members = rows.sorted {
                $0.memory == $1.memory ? $0.id.pid < $1.id.pid : ($0.memory ?? 0) > ($1.memory ?? 0)
            }
            let owner: URL?
            let primary: TrayProcess?
            let name: String
            switch id {
            case .application(let url, _):
                owner = url
                let mains = members.filter { registered[$0.id.pid]?.url.standardizedFileURL.path == url.path }
                if mains.count == 1, let main = mains.first {
                    primary = main
                    name = registered[main.id.pid]?.name ?? url.deletingPathExtension().lastPathComponent
                } else {
                    let bundle = Bundle(url: url)
                    let executable = bundle?.executableURL?.standardizedFileURL.path
                    let candidates = members.filter { $0.executable == executable }
                    primary = candidates.count == 1 ? candidates.first : nil
                    name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                        ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                        ?? url.deletingPathExtension().lastPathComponent
                }
            case .process:
                primary = members[0]
                name = members[0].name
                owner = nil
            }
            func sum(_ key: KeyPath<TrayProcess, Double?>) -> Double? {
                let values = members.compactMap { $0[keyPath: key] }.filter { $0.isFinite && $0 >= 0 }
                return values.isEmpty ? nil : values.reduce(0, +)
            }
            return Self(id: id, name: name, application: owner, members: members, primary: primary,
                        memory: members.allSatisfy { $0.memory != nil } ? members.compactMap(\.memory).reduce(0, +) : nil, cpu: sum(\.cpuPercent), energyScore: ProcessEnergyScore(members))
        }
    }

    func matches(_ term: String) -> Bool {
        term.isEmpty || name.localizedCaseInsensitiveContains(term) || members.contains {
            $0.name.localizedCaseInsensitiveContains(term) || String($0.id.pid).contains(term)
        }
    }

    @MainActor static func registeredApplications() -> [pid_t: Application] {
        var apps: [pid_t: Application] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let url = app.bundleURL {
                apps[app.processIdentifier] = Application(url: url, name: app.localizedName)
            }
        }
        return apps
    }
}

struct ProcessEnergyScore {
    static let help = "Score énergétique sur 20. La note combine la charge CPU et les réveils du processeur. Plus elle est élevée, plus le processus est actif. 20 correspond à un cœur occupé en continu, réveils compris."
    let value: Double
    let isLowerBound: Bool

    init?(_ members: [TrayProcess]) {
        var load = 0.0
        var hasCPU = false
        var partial = false
        for member in members {
            if let cpu = member.cpuPercent, cpu.isFinite, cpu >= 0 {
                load += cpu
                hasCPU = true
            } else { partial = true }
            if let wakeups = member.idleWakeupsPerSecond, wakeups.isFinite, wakeups >= 0 {
                // Pondération de top sur macOS : 500 µs de temps actif par réveil de veille.
                load += wakeups * 0.05
            } else { partial = true }
        }
        guard hasCPU else { return nil }
        value = min(20, load / 5)
        isLowerBound = partial && value < 20
    }

    var number: String { value.formatted(.number.precision(.fractionLength(0...1))) }

    var label: String {
        if value > 0 && value < 0.1 { return isLowerBound ? "> 0/20" : "< " + 0.1.formatted(.number) + "/20" }
        return (isLowerBound ? "≥ " : "") + number + "/20"
    }
}

enum ProcessCPULevel {
    case normal, elevated, critical

    init(_ percent: Double?) {
        if let percent, percent > 80 { self = .critical }
        else if let percent, percent > 40 { self = .elevated }
        else { self = .normal }
    }

    var accent: NSColor? {
        switch self {
        case .normal: return nil
        case .elevated: return .systemOrange
        case .critical: return .systemRed
        }
    }
}

enum HomeProcessMetric {
    static func cpu(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...1))) + " %"
    }

    static func memory(_ bytes: UInt64?) -> String { bytes.map { humanSize($0, fractionalAbove: 1_000_000_000) } ?? "—" }
}
