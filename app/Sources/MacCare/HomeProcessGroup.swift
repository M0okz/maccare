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
    let power: Double?
    var cpuLevel: ProcessCPULevel { ProcessCPULevel(cpu) }

    var cpuLabel: String { lowerBound(cpu, key: \.cpuPercent) + HomeProcessMetric.cpu(cpu) }
    var powerLabel: String {
        let bound = lowerBound(power, key: \.energyWatts)
        if !bound.isEmpty, let power, power > 0 && power < 0.001 { return "> 0 mW" }
        return bound + HomeProcessMetric.power(power)
    }

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
                        memory: members.allSatisfy { $0.memory != nil } ? members.compactMap(\.memory).reduce(0, +) : nil, cpu: sum(\.cpuPercent), power: sum(\.energyWatts))
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

    static func power(_ watts: Double?) -> String {
        guard let watts else { return "—" }
        if watts == 0 { return "0 W" }
        if watts < 0.001 { return "< 1 mW" }
        if watts < 1 { return (watts * 1000).formatted(.number.precision(.fractionLength(0))) + " mW" }
        return watts.formatted(.number.precision(.fractionLength(0...2))) + " W"
    }

    static func memory(_ bytes: UInt64?) -> String { bytes.map { humanSize($0, fractionalAbove: 1_000_000_000) } ?? "—" }
}
