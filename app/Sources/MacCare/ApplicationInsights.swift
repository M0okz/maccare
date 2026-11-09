import Foundation
import AppKit

struct ApplicationInsightItem: Identifiable, Hashable {
    let app: AppInfo
    let detail: String
    let lastUsed: Date?
    var id: String { app.id }
}

struct ApplicationUsageEvidence {
    let lastUsed: Date?
    let added: Date?
    let running: Bool
    let background: Bool
}

enum ApplicationInsightPolicy {
    static let unusedDays = 30
    static let graceDays = 30

    static func isUnused(_ evidence: ApplicationUsageEvidence, now: Date, days: Int = unusedDays) -> Bool {
        guard !evidence.running, !evidence.background, let used = evidence.lastUsed, let added = evidence.added,
              used <= now, added <= now else { return false }
        return now.timeIntervalSince(used) >= Double(days) * 86_400 &&
               now.timeIntervalSince(added) >= Double(graceDays) * 86_400
    }

    /// Only definite blockers. Intel on Apple Silicon may run with Rosetta and is not rejected.
    static func incompatibility(architectures: Set<String>?, minimum: String?, perArchitecture: [String: String],
                                system: String, appleSilicon: Bool) -> String? {
        let supported: Set<String> = appleSilicon ? ["arm64", "arm64e", "x86_64", "x86_64h"] : ["x86_64", "x86_64h"]
        if let architectures, !architectures.isEmpty, architectures.isDisjoint(with: supported) {
            return "Architecture non prise en charge : " + architectures.sorted().joined(separator: ", ")
        }
        let usable = architectures.map { $0.intersection(supported) } ?? []
        let values: [String?] = usable.isEmpty ? [minimum] : usable.flatMap { architecture -> [String?] in
            var requirements = [perArchitecture[architecture] ?? minimum]
            // The native reader returns CPU families, not subtypes. Only claim a
            // blocker when every declared variant of that family needs a newer OS.
            let variant = architecture == "arm64" ? "arm64e" : architecture == "x86_64" ? "x86_64h" : nil
            if let variant, let requirement = perArchitecture[variant] {
                requirements.append(requirement)
            }
            return requirements
        }
        guard values.allSatisfy({ $0 != nil }) else { return nil }
        let requirements = values.compactMap { $0 }
        guard !requirements.isEmpty,
              requirements.allSatisfy({ ApplicationReleaseVersion.isNewer($0, than: system) }),
              let required = requirements.min(by: { $0.compare($1, options: .numeric) == .orderedAscending }) else { return nil }
        return "Nécessite macOS \(required) ou ultérieur · ce Mac utilise macOS \(system)"
    }
}

struct ApplicationInsightsSnapshot {
    var unused: [ApplicationInsightItem] = []
    var incompatible: [ApplicationInsightItem] = []
    var unknownUsage = 0
    var unknownCompatibility = 0
    var installers: [ScanItem] = []
    var installerRule: String?
    var installerError: String?
}

enum ApplicationInsightsReader {
    static func scan(apps: [AppInfo], running: Set<String>, now: Date = Date()) -> ApplicationInsightsSnapshot {
        var result = ApplicationInsightsSnapshot()
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let system = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        #if arch(arm64)
        let arm = true
        #else
        let arm = false
        #endif
        for app in apps {
            guard let bundle = Bundle(url: app.url) else { result.unknownCompatibility += 1; result.unknownUsage += 1; continue }
            let metadata = NSMetadataItem(url: app.url)
            let used = metadata?.value(forAttribute: "kMDItemLastUsedDate") as? Date
            let added = metadata?.value(forAttribute: "kMDItemDateAdded") as? Date
            let background = (bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true) ||
                             (bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool == true)
            let evidence = ApplicationUsageEvidence(lastUsed: used, added: added,
                                                   running: app.bundleId.map(running.contains) ?? false, background: background)
            if used == nil || added == nil { result.unknownUsage += 1 }
            if ApplicationInsightPolicy.isUnused(evidence, now: now), let used {
                let days = Int(now.timeIntervalSince(used) / 86_400)
                result.unused.append(.init(app: app, detail: "Aucune ouverture enregistrée depuis \(days) jours", lastUsed: used))
            }
            let architectures = bundle.executableURL.flatMap { ExecutableArchitectures.read(at: $0) }
            if architectures == nil { result.unknownCompatibility += 1 }
            let minimum = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String
            let perArch = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersionByArchitecture") as? [String: String] ?? [:]
            if let detail = ApplicationInsightPolicy.incompatibility(architectures: architectures, minimum: minimum,
                perArchitecture: perArch, system: system, appleSilicon: arm) {
                result.incompatible.append(.init(app: app, detail: detail, lastUsed: used))
            }
        }
        // Reuse the shipped, closed DMG/PKG rule and the engine's file identity guards.
        if let category = CleaningCategory.all.first(where: { $0.id == "downloads.installers" }) {
            result.installerRule = category.baseTOML
            do { result.installers = try Engine.scan(ruleTOML: category.baseTOML).sorted { $0.size_bytes > $1.size_bytes } }
            catch { result.installerError = "Lecture de Téléchargements incomplète : \(error.localizedDescription)" }
        } else { result.installerError = "La règle des installateurs est indisponible dans ce paquet." }
        result.unused.sort { ($0.lastUsed ?? .distantFuture) < ($1.lastUsed ?? .distantFuture) }
        return result
    }
}
