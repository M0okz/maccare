import Foundation
import XCTest
@testable import MacCare

final class AppStoreUpdateInstallationTests: XCTestCase {
    private func withTarget(_ exercise: (ApplicationUpdateTarget) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = root.appendingPathComponent("Windows App.app")
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = ApplicationUpdateTarget(url: url, bundleID: "org.example.store-fixture", version: "11.4.4", expectedVersion: "11.4.5")
        try writeVersion(target.version, target: target)
        try await exercise(target)
    }

    private func writeVersion(_ version: String, target: ApplicationUpdateTarget) throws {
        let info = ["CFBundleIdentifier": target.bundleID, "CFBundleShortVersionString": version]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: target.url.appendingPathComponent("Contents/Info.plist"), options: .atomic)
    }

    func testSilentStoreCannotKeepTheInstallerBusyIndefinitely() async throws {
        try await withTarget { target in
            let start = ContinuousClock.now
            let installed = try await AppStoreUpdateInstallation.run("/bin/sleep", ["3"], target: target,
                                                                     timeout: .milliseconds(150), poll: .milliseconds(20))
            XCTAssertFalse(installed)
            XCTAssertLessThan(start.duration(to: .now), .seconds(2))
        }
    }

    func testConfirmsInstalledVersionWhileStoreCommandIsStillWaiting() async throws {
        try await withTarget { target in
            let change = Task {
                try await Task.sleep(for: .milliseconds(100))
                try self.writeVersion(target.expectedVersion, target: target)
            }
            defer { change.cancel() }
            let start = ContinuousClock.now
            let installed = try await AppStoreUpdateInstallation.run("/bin/sleep", ["3"], target: target,
                                                                     timeout: .seconds(2), poll: .milliseconds(20))
            XCTAssertTrue(installed)
            XCTAssertLessThan(start.duration(to: .now), .seconds(2))
            try await change.value
        }
    }

    func testSuccessfulCommandAloneDoesNotConfirmAnInstallation() async throws {
        try await withTarget { target in
            let installed = try await AppStoreUpdateInstallation.run("/usr/bin/true", [], target: target,
                                                                     poll: .milliseconds(20), confirmationGrace: .milliseconds(80))
            XCTAssertFalse(installed)
        }
    }

    func testStoppingObservationReturnsAnUnconfirmedResult() async throws {
        try await withTarget { target in
            let start = ContinuousClock.now
            let observer = Task {
                try await AppStoreUpdateInstallation.run("/bin/sleep", ["3"], target: target,
                                                         poll: .milliseconds(20))
            }
            try await Task.sleep(for: .milliseconds(100))
            observer.cancel()
            let installed = try await observer.value
            XCTAssertFalse(installed)
            XCTAssertLessThan(start.duration(to: .now), .seconds(2))
        }
    }

    func testStoreFailureKeepsTheDiagnostic() async throws {
        try await withTarget { target in
            do {
                _ = try await AppStoreUpdateInstallation.run("/bin/sh", ["-c", "echo 'store fixture refused' >&2; exit 1"],
                                                             target: target, poll: .milliseconds(20))
                XCTFail("Une demande refusée doit signaler son erreur.")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("store fixture refused"))
            }
        }
    }

    func testVersionArrivingAfterCommandExitIsConfirmed() async throws {
        try await withTarget { target in
            let change = Task {
                try await Task.sleep(for: .milliseconds(100))
                try self.writeVersion(target.expectedVersion, target: target)
            }
            defer { change.cancel() }
            let installed = try await AppStoreUpdateInstallation.run("/usr/bin/true", [], target: target,
                                                                     poll: .milliseconds(20), confirmationGrace: .seconds(2))
            XCTAssertTrue(installed)
            try await change.value
        }
    }
}
