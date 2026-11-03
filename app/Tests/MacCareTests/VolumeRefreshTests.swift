import XCTest
import AppKit
@testable import MacCare

@MainActor
final class VolumeRefreshTests: XCTestCase {
    private let boot = SpaceModel.Root(name: "Disque QA", path: "/")
    private let alpha = SpaceModel.Root(name: "Alpha QA", path: "/Volumes/MacCare-QA-Alpha")
    private let beta = SpaceModel.Root(name: "Beta QA", path: "/Volumes/MacCare-QA-Beta")
    private final class Source { var volumes: [SpaceModel.Root] = [] }

    func testRefreshRemovesEjectedVolumeAndIncludesNewMountWithoutScan() {
        let source = Source()
        source.volumes = [boot, alpha]
        let model = SpaceModel(measure: { _, _ in XCTFail("Le menu ne doit pas lancer de mesure"); return [] }, volumeProvider: { source.volumes }, volumeEvents: NotificationCenter())
        source.volumes = [boot, beta]
        model.refreshVolumes()
        XCTAssertEqual(model.volumes, [boot, beta])
        XCTAssertFalse(model.roots.contains(alpha))
        XCTAssertTrue(model.locationChoices.contains(beta))
        XCTAssertFalse(model.isLoading)
    }

    func testEjectingSelectedVolumeCancelsAndDiscardsLateResult() async throws {
        let source = Source()
        source.volumes = [boot, alpha]
        let model = SpaceModel(measure: { path, _ in
            Thread.sleep(forTimeInterval: 0.05)
            return [SpaceChild(path: path + "/QA-file", size_bytes: 100, is_dir: false, measured: true)]
        }, volumeProvider: { source.volumes }, volumeEvents: NotificationCenter())
        model.setRoot(alpha)
        XCTAssertTrue(model.isLoading)
        source.volumes = [boot]
        model.refreshVolumes()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(model.root, boot)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.hasMeasured)
        XCTAssertTrue(model.children.isEmpty)
        XCTAssertNotNil(model.statusMessage)
        XCTAssertFalse(model.locationChoices.contains(alpha))
    }

    func testUnrelatedVolumeChangesPreserveSelectedFolder() {
        let source = Source()
        source.volumes = [boot, alpha]
        let model = SpaceModel(volumeProvider: { source.volumes }, volumeEvents: NotificationCenter())
        model.selectFolder(URL(fileURLWithPath: NSHomeDirectory()))
        let selected = model.root
        source.volumes = [boot, beta]
        model.refreshVolumes()
        XCTAssertEqual(model.root, selected)
        XCTAssertTrue(model.locationChoices.contains(selected))
        XCTAssertFalse(model.locationChoices.contains(alpha))
        XCTAssertFalse(model.isLoading)
    }

    func testWorkspaceUnmountNotificationUpdatesList() async throws {
        let source = Source()
        source.volumes = [boot, alpha]
        let events = NotificationCenter()
        let model = SpaceModel(volumeProvider: { source.volumes }, volumeEvents: events)
        source.volumes = [boot]
        events.post(name: NSWorkspace.didUnmountNotification, object: nil)
        for _ in 0..<100 {
            if !model.volumes.contains(alpha) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(model.volumes, [boot])
        XCTAssertFalse(model.isLoading)
    }
}
