import XCTest
@testable import MacCare

@MainActor
final class SmartScanApplicationsTests: XCTestCase {
    private func category(_ id: String, type: String, root: URL, review: Bool = false) throws -> CleaningCategory {
        try XCTUnwrap(RuleCatalog.category(fromTOML: """
            id = "\(id)"
            category = "\(type)"
            version = 1
            root = "\(tomlEscape(root.path))"
            risk = "\(review ? "review" : "safe")"
            """))
    }

    func testTenProfilesAndUnattributedItemsPartitionTheOriginalResult() throws {
        let root = URL(fileURLWithPath: "/fixture")
        let cache = try category("cache.generic", type: "user-cache", root: root)
        let archives = try category("xcode.archives", type: "xcode-archives", root: root, review: true)
        func item(_ name: String, _ category: CleaningCategory, owner: String? = nil) -> ScanItem {
            ScanItem(id: UUID().uuidString, path: root.appendingPathComponent(name).path, category: category.category,
                     size_bytes: 128, reason: category.id, autoselect: false, identity: .init(device: 1, inode: 1), owner: owner)
        }
        let unassigned = ["Google", "Slack-old", "Microsoft", "com.spotify.client.backup"].map { item($0, cache) }
        let names = ["Google/Chrome", "Slack", "com.spotify.client/Browser/Cache", "Code", "Firefox", "Discord", "Notion", "us.zoom.xos", "MSTeams"]
        let known = names.map { item($0, cache, owner: $0.contains("/") ? String($0.split(separator: "/")[0]) : nil) }
        let xcode = item("2026-11-26", archives)
        let groups = [ScanGroup(category: cache, items: known + unassigned), ScanGroup(category: archives, items: [xcode])]
        let result = SmartScanAppResult.group(groups)
        XCTAssertEqual(SmartScanAppProfile.supported.count, 10)
        XCTAssertEqual(result.count, 11)
        for app in result where app.id != "other" { XCTAssertEqual(app.count, 1, app.id) }
        XCTAssertEqual(result.last?.items.map(\.id), unassigned.map(\.id))
        XCTAssertEqual(result.flatMap(\.items).count, known.count + unassigned.count + 1)
        XCTAssertEqual(Set(result.flatMap(\.items).map(\.id)), Set(groups.flatMap(\.items).map(\.id)))
        XCTAssertEqual(result.reduce(0) { $0 + $1.bytes }, groups.reduce(0) { $0 + $1.size })
        XCTAssertEqual(result.first { $0.profile.name == "Xcode" }?.sections.first?.category.risk, .review)
        let uuid = UUID().uuidString
        let sandbox = try category("cache.containers", type: "container-cache", root: root)
        let wrapped = item("Data/Library/Caches", sandbox, owner: uuid)
        XCTAssertEqual(SmartScanAppProfile.identifier(for: wrapped, containerOwners: [uuid: "com.microsoft.teams2"]), "com.microsoft.teams2")
        XCTAssertFalse(SmartScanAppProfile.includes(wrapped, containerOwners: [uuid: "com.spotify.client"]))
        XCTAssertTrue(SmartScanAppProfile.includes(wrapped, containerOwners: [uuid: "com.microsoft.teams2"]))
        let shared = try category("cache.group-containers", type: "group-container-cache", root: root)
        XCTAssertEqual(SmartScanAppProfile.identifier(for: item("Library/Caches", shared, owner: "Slack"), containerOwners: [:]), "other")
    }

    func testDetailUsesTheSameSelectionAndOnlyCleansItsOwnSelectedItems() async throws {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/MacCareFixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rule = try category("cache.fixture", type: "user-cache", root: root)
        for file in ["Slack", "com.tinyspeck.slackmacgap", "Discord", "Unassigned"] {
            try Data(repeating: 1, count: 4096).write(to: root.appendingPathComponent(file))
        }
        let suite = testPreferencesSuite("SmartScanApplications")
        let prefs = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite) }
        prefs.set(true, forKey: "directDelete")
        let model = SmartScanModel(categories: { [rule] }, defaults: prefs, makeCacheLookup: { { _, _ in [] } })
        model.scan()
        try await finish(model)
        let slack = try XCTUnwrap(model.applications.first { $0.profile.name == "Slack" })
        XCTAssertEqual(slack.count, 2)
        let keep = try XCTUnwrap(slack.items.first { $0.url.lastPathComponent == "Slack" })
        model.toggle(keep)
        XCTAssertFalse(model.isGroupFullySelected(try XCTUnwrap(model.groups.first)))
        let selectedElsewhere = model.selection.subtracting(slack.items.map(\.id))
        model.cleanSelected(in: slack.id)
        try await finish(model)
        XCTAssertEqual(model.cleanup?.report.removed, 1)
        XCTAssertEqual(model.selection, selectedElsewhere)
        XCTAssertEqual(model.applications.first { $0.id == slack.id }?.items.map(\.id), [keep.id])
        for preserved in ["Slack", "Discord", "Unassigned"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(preserved).path))
        }
    }

    private func finish(_ model: SmartScanModel) async throws {
        for _ in 0..<300 {
            if model.stage == .results { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Le Smart Scan ne rend pas la main")
    }
}
