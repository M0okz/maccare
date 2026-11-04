import AppKit

struct MemoryAlertApplication {
    let pid: pid_t
    let name: String
    let bundleID: String
    let bundlePath: String
    let executable: String
    let isRegular: Bool

    @MainActor static func running(_ pid: pid_t) -> Self? {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              let bundle = app.bundleURL, let executable = app.executableURL else { return nil }
        return Self(pid: pid, name: app.localizedName ?? bundle.deletingPathExtension().lastPathComponent,
                    bundleID: app.bundleIdentifier ?? "", bundlePath: bundle.path,
                    executable: executable.path, isRegular: app.activationPolicy == .regular)
    }
}
