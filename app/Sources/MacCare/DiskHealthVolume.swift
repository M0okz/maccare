import Foundation

struct DiskHealthVolume: Identifiable, Hashable {
    let path: String
    let name: String
    var id: String { path }
    static func mounted() -> [DiskHealthVolume] {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsLocalKey, .volumeIsBrowsableKey]
        let root = URL(fileURLWithPath: "/")
        let startupName = (try? root.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "Disque de démarrage"
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        var seen: Set<String> = ["/"]
        return [DiskHealthVolume(path: "/", name: startupName + " · disque de démarrage")] + urls.compactMap { url in
            guard let info = try? url.resourceValues(forKeys: keys), info.volumeIsLocal == true,
                  info.volumeIsBrowsable != false, seen.insert(url.path).inserted else { return nil }
            return DiskHealthVolume(path: url.path, name: info.volumeName ?? url.lastPathComponent)
        }
    }
}
