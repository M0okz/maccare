import SwiftUI
import AppKit
import Combine

// A state stand-in drives the shipping About view and window code without Sparkle, scans or hardware.
@MainActor final class AppUpdater: ObservableObject {
    @Published var availableVersion: String? = ProcessInfo.processInfo.environment["MACCARE_TOOLBAR_QA_START_VISIBLE"] == "1" ? "9.9.9" : nil
    @Published var canCheckForUpdates = true
    @Published var releaseNotes: String? = "Une nouvelle version de MacCare.\n\n- **Amélioration** de la stabilité.\n- Corrections et nouveautés."
    var lastCheckDate: Date? = Date()
    var unavailableReason: String?
    func checkForUpdates() { print("CHECK_REQUESTED");fflush(stdout) }
}
@main struct ToolbarProbe: App {
    @StateObject private var updater = AppUpdater()
    @State private var step = 0
    var body: some Scene {
        WindowGroup {
            HStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text("Navigation de test").font(.caption).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("Mes outils").font(AppFont.body).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
                    AboutSidebarButton(selected: true, compact: false,
                                       updateAvailable: updater.availableVersion != nil) {}
                }
                .padding(.horizontal, 10).padding(.top, 70).padding(.bottom, 44)
                .frame(width: 240).background(Theme.sidebar)
                AboutView(updater: updater)
            }
            .background(LinearGradient(colors: [Theme.window, Theme.bg], startPoint: .top, endPoint: .bottom))
            .foregroundStyle(Theme.fg).tint(Theme.accent).preferredColorScheme(.dark)
            .frame(minWidth:700,minHeight:480)
            .background(WindowConfigurator())
            .task { @MainActor in
                if let directory = ProcessInfo.processInfo.environment["MACCARE_ABOUT_CAPTURE_DIR"] {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    for (name, size, available) in [
                        ("available", NSSize(width: 1200, height: 800), true),
                        ("no-update", NSSize(width: 1200, height: 720), false),
                        ("narrow", NSSize(width: 860, height: 620), true)
                    ] {
                        updater.availableVersion = available ? "9.9.9" : nil
                        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { exit(1) }
                        window.setContentSize(size)
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard let content = window.contentView,
                              let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { exit(1) }
                        content.cacheDisplay(in: content.bounds, to: bitmap)
                        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
                    }
                }
                var identities = Set<ObjectIdentifier>()
                var windowChecks = 0
                for i in 0..<160 {
                    updater.availableVersion = i % 4 < 2 ? nil : "9.9.9"
                    step = i
                    try? await Task.sleep(nanoseconds:40_000_000)
                    if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                        if let toolbar = window.toolbar { identities.insert(ObjectIdentifier(toolbar)) }
                        guard !(window.toolbar?.items ?? []).contains(where: { $0.itemIdentifier.rawValue.contains("MacCareUpdateAvailability") }) else {
                            print("REMOVED_TOOLBAR_ITEM_RETURNED"); fflush(stdout); exit(1)
                        }
                        windowChecks += 1
                    }
                }
                if windowChecks == 0 { print("NO_WINDOW_CHECKS"); fflush(stdout); exit(1) }
                print("TOOLBAR_PROBE completed=160 toolbarIdentities=\(identities.count) windowChecks=\(windowChecks)");fflush(stdout)
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
