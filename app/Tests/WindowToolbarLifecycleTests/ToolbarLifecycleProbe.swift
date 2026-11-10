import SwiftUI
import AppKit
import Combine

// A state stand-in drives the shipping button, toolbar and window code without Sparkle, scans or hardware.
@MainActor final class AppUpdater: ObservableObject {
    @Published var availableVersion: String? = ProcessInfo.processInfo.environment["MACCARE_TOOLBAR_QA_START_VISIBLE"] == "1" ? "9.9.9" : nil
    @Published var canCheckForUpdates = true
    func checkForUpdates() { print("CHECK_REQUESTED");fflush(stdout) }
}
@main struct ToolbarProbe: App {
    @StateObject private var updater = AppUpdater()
    @State private var showNotice = true
    @State private var step = 0
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.purple.opacity(0.2)
                Text("Toolbar lifecycle probe \(step)")
            }
            .frame(minWidth:700,minHeight:480)
            .toolbar { AppUpdateAvailabilityToolbar(updater:updater,isVisible:showNotice) }
            .background(WindowConfigurator())
            .task { @MainActor in
                var identities = Set<ObjectIdentifier>()
                for i in 0..<160 {
                    updater.availableVersion = i % 4 < 2 ? nil : "9.9.9"
                    showNotice = i % 5 != 0
                    step = i
                    try? await Task.sleep(nanoseconds:40_000_000)
                    if let toolbar = NSApp.windows.first(where:{$0.canBecomeMain})?.toolbar { identities.insert(ObjectIdentifier(toolbar)) }
                }
                print("TOOLBAR_PROBE completed=160 toolbarIdentities=\(identities.count)");fflush(stdout)
                if let domain = Bundle.main.bundleIdentifier, domain.hasPrefix("org.maccare.toolbar-regression-probe.") {
                    UserDefaults.standard.removePersistentDomain(forName: domain)
                }
                NSApp.terminate(nil)
            }
        }.windowStyle(.hiddenTitleBar).defaultSize(width:900,height:600)
    }
}
// Unused DesignSystem row dependencies; no file scan is performed by this probe.
struct ScanItem { let path: String; let displayName: String; let size_bytes: UInt64 }
func humanSize(_ bytes: UInt64) -> String { String(bytes) }
