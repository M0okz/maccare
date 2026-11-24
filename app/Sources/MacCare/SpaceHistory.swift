import CryptoKit
import Foundation

enum SpaceComparison {
    case unavailable(String)
    case baseline
    case compared(since: Date, changes: [Change])

    struct Change: Identifiable {
        let name: String
        let before: SpaceHistory.Folder?
        let after: SpaceHistory.Folder?
        var id: String { name }
        var partial: Bool { before?.complete == false || after?.complete == false }
        var growth: Bool { (after?.bytes ?? 0) >= (before?.bytes ?? 0) }
        var magnitude: UInt64 {
            let a = before?.bytes ?? 0, b = after?.bytes ?? 0
            return max(a, b) - min(a, b)
        }
        var label: String {
            if partial { return "Mesure partielle" }
            let amount = magnitude == 0 ? humanSize(0) : (growth ? "+" : "−") + humanSize(magnitude)
            if before == nil { return "Nouveau · " + amount }
            if after == nil { return "Disparu · " + amount }
            return amount
        }
    }
}

/// Une paire de mesures par dossier. Le volume et l’inode empêchent de comparer
/// deux disques ou deux dossiers successifs montés au même chemin.
struct SpaceHistory {
    struct Scope: Equatable {
        let path: String
        let volume: String
        let inode: UInt64

        static func read(_ path: String) -> Scope? {
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
            guard let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString,
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
            return Scope(path: url.path, volume: volume, inode: inode.uint64Value)
        }

        var filename: String {
            let data = Data("\(volume)\u{0}\(inode)\u{0}\(path)".utf8)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + ".json"
        }
    }

    struct Folder: Codable {
        let bytes: UInt64
        let complete: Bool
    }

    private struct Sample: Codable {
        let date: Date
        let folders: [String: Folder]

        init(children: [SpaceChild], date: Date) {
            self.date = date
            var folders: [String: Folder] = [:]
            for child in children where child.is_dir {
                folders[child.name] = Folder(bytes: child.size_bytes, complete: child.measured)
            }
            self.folders = folders
        }

        func compared(to old: Sample) -> SpaceComparison {
            let changes = Set(folders.keys).union(old.folders.keys).compactMap { name -> SpaceComparison.Change? in
                let change = SpaceComparison.Change(name: name, before: old.folders[name], after: folders[name])
                if !change.partial, change.magnitude == 0, change.before != nil, change.after != nil { return nil }
                return change
            }.sorted {
                if $0.partial != $1.partial { return !$0.partial }
                if !$0.partial, $0.magnitude != $1.magnitude { return $0.magnitude > $1.magnitude }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return .compared(since: old.date, changes: changes)
        }
    }

    private struct Pair: Codable {
        let previous: Sample?
        let latest: Sample
    }

    let directory: URL
    static var applicationStore: Self {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Self(directory: support.appendingPathComponent(AppBuildIdentity.name + "/SpaceHistory-v1", isDirectory: true))
    }

    // Appelé hors du thread principal. Le verrou couvre la rotation des deux mesures
    // et l’éviction si deux instances terminent leur analyse au même moment.
    func record(_ children: [SpaceChild], date: Date, scope: Scope) throws -> SpaceComparison {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(directory.path, O_RDONLY)
        guard fd >= 0 else { throw POSIXError(.EACCES) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        let url = directory.appendingPathComponent(scope.filename)
        let sample = Sample(children: children, date: date)
        let previous: Pair?
        do {
            previous = try JSONDecoder().decode(Pair.self, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            previous = nil
        } catch is DecodingError {
            // Un historique illisible reprend à partir de la mesure courante.
            previous = nil
        }
        if let previous, previous.latest.date > date {
            return .unavailable("Une mesure plus récente est déjà enregistrée. Actualisez pour la comparer.")
        }
        let pair = Pair(previous: previous?.latest, latest: sample)
        try JSONEncoder().encode(pair).write(to: url, options: .atomic)
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "json" && $0 != url }
        if files.count >= 12 {
            let dated = try files.map { ($0, try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) }
            for (stale, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(11) {
                try fm.removeItem(at: stale)
            }
        }
        return pair.previous.map { sample.compared(to: $0) } ?? .baseline
    }
}
