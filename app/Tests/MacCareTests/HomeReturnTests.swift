import AppKit
import SwiftUI
import XCTest
@testable import MacCare

@MainActor
final class HomeReturnTests: XCTestCase {
    func testReturningFromApplicationsDisplaysTheLastProcessSample() async throws {
        let app = AppState(startBackgroundServices: false)
        let detail = DetailView(app: app, updater: AppUpdater(), layout: .standard)
            .modifier(HomeProcessModal())
        let host = NSHostingView(rootView: detail)
        // Keep the window offscreen so the live sampler cannot replace the fixture.
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1211, height: 773),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        let initial = try XCTUnwrap(processList(in: host))
        let process = TrayProcess(id: .init(pid: 999_999, startedSeconds: 1, startedMicroseconds: 0),
                                 name: "Home Return Fixture", userID: getuid(), memory: 4096,
                                 cpuPercent: 0, executable: "/tmp/home-return-fixture")
        initial.owner.controller.record([process])
        try await wait(in: host) { $0?.owner.rows.first?.representative.id == process.id }

        app.select(.applications)
        try await wait(in: host) { $0 == nil }
        app.select(.home)
        try await wait(in: host) { $0 != nil }
        let returned = try XCTUnwrap(processList(in: host))
        XCTAssertEqual(returned.owner.rows.map(\.representative.id), [process.id])
    }

    private func wait(in host: NSView, until matches: (HomeProcessList.Coordinator?) -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            host.layoutSubtreeIfNeeded()
            if matches(processList(in: host)) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("La liste des processus n’a pas atteint l’état attendu.")
    }

    private func processList(in view: NSView) -> HomeProcessList.Coordinator? {
        if let table = view as? NSTableView, let list = table.dataSource as? HomeProcessList.Coordinator {
            return list
        }
        for child in view.subviews {
            if let list = processList(in: child) { return list }
        }
        return nil
    }
}
