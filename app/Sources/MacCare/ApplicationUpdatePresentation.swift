import Foundation

struct ApplicationUpdateEntry: Identifiable {
    let source: UpdateSource
    let item: OutdatedItem
    var id: String { source.key + ":" + item.id }
    var versions: (current: String, available: String)? {
        for separator in ["→", "->", "!="] {
            let parts = item.detail.components(separatedBy: separator)
            if parts.count == 2 {
                let trim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "()"))
                let current = parts[0].trimmingCharacters(in: trim)
                let available = parts[1].trimmingCharacters(in: trim)
                if !current.isEmpty && !available.isEmpty { return (current, available) }
            }
        }
        return nil
    }
    func applicationURL(in apps: [AppInfo]) -> URL? {
        if let url = item.applicationURL { return url }
        func normalized(_ name: String) -> String { name.lowercased().filter { $0.isLetter || $0.isNumber } }
        return apps.first { normalized($0.name) == normalized(item.name) }?.url
    }
    var sourceName: String {
        switch source.key {
        case "cask": return "Homebrew"
        case "mas": return "App Store"
        case "netnewswire": return "Sparkle"
        default: return source.title
        }
    }
}

enum ApplicationUpdateSort: String, CaseIterable, Identifiable {
    case recent, name, size
    var id: String { rawValue }
    var title: String {
        switch self { case .recent: return "Dernière ouverture"; case .name: return "Nom"; case .size: return "Taille" }
    }
}

enum ApplicationUpdatePresentation {
    static func entries(sources: [UpdateSource], apps: [AppInfo], query: String, sort: ApplicationUpdateSort,
                        lastOpened: [URL: Date]) -> [ApplicationUpdateEntry] {
        sources.filter { ["cask", "mas", "netnewswire"].contains($0.key) }
            .flatMap { source in source.items.map { ApplicationUpdateEntry(source: source, item: $0) } }
            .filter { query.isEmpty || $0.item.name.localizedCaseInsensitiveContains(query) || $0.sourceName.localizedCaseInsensitiveContains(query) }
            .sorted { a, b in
                switch sort {
                case .recent:
                    let left = a.applicationURL(in: apps).flatMap { lastOpened[$0] }
                    let right = b.applicationURL(in: apps).flatMap { lastOpened[$0] }
                    if left != right { return (left ?? .distantPast) > (right ?? .distantPast) }
                case .size:
                    if a.item.downloadBytes != b.item.downloadBytes { return (a.item.downloadBytes ?? 0) > (b.item.downloadBytes ?? 0) }
                case .name: break
                }
                let order = a.item.name.localizedStandardCompare(b.item.name)
                return order == .orderedSame ? a.id < b.id : order == .orderedAscending
            }
    }
    static func publicationDate(_ value: String) -> Date? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return parser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    static func publicationLabel(_ value: String) -> String {
        guard let date = publicationDate(value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = TimeZone(identifier: "Europe/Paris")
        formatter.dateStyle = .medium; formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    static func displayNotes(_ value: String?) -> String {
        let cleaned = notes(value ?? "")
        return cleaned.isEmpty ? "Les notes de version ne sont pas fournies par cette source." : cleaned
    }
    static func notes(_ value: String) -> String {
        var lines: [String] = []
        for line in value.components(separatedBy: .newlines) {
            let cleaned = line.trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty || (lines.last != nil && lines.last != "") { lines.append(cleaned) }
        }
        while lines.last == "" { lines.removeLast() }
        func bullet(_ line: String) -> Bool { ["•", "—", "–", "- ", "* "].contains { line.hasPrefix($0) } }
        return lines.enumerated().filter { index, line in
            guard line.isEmpty, index > 0, index + 1 < lines.count else { return true }
            return !(bullet(lines[index + 1]) && (bullet(lines[index - 1]) || lines[index - 1].hasSuffix(":")))
        }.map(\.element).joined(separator: "\n")
    }
}
