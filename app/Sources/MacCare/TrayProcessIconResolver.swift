import AppKit

@MainActor
struct TrayProcessIconResolver {
    private let applicationIcon: (URL) -> NSImage?

    init() { applicationIcon = Self.loadApplicationIcon }
    init(applicationIcon: @escaping (URL) -> NSImage?) { self.applicationIcon = applicationIcon }

    func icon(executable: String, registeredBundleURL: URL?, registeredIcon: NSImage?) -> NSImage? {
        let executableOwner = Self.owningApplication(in: executable)
        if executableOwner == nil && ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/System/"].contains(where: executable.hasPrefix) {
            return nil
        }
        guard let owner = executableOwner ?? registeredBundleURL.flatMap({ Self.owningApplication(in: $0.path) }) else {
            return nil
        }
        if owner.path == registeredBundleURL?.standardizedFileURL.path, let registeredIcon { return registeredIcon }
        return applicationIcon(owner)
    }

    nonisolated static func owningApplication(in path: String) -> URL? {
        guard path.hasPrefix("/") else { return nil }
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard let index = components.firstIndex(where: { ($0 as NSString).pathExtension.lowercased() == "app" }) else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(components.prefix(index + 1))), isDirectory: true)
    }

    private static func loadApplicationIcon(at url: URL) -> NSImage? {
        guard let bundle = Bundle(url: url), bundle.executableURL != nil else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
