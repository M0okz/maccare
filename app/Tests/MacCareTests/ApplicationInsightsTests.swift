import XCTest
@testable import MacCare

final class ApplicationInsightsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private func evidence(used: Int? = 31, added: Int? = 60, running: Bool = false, background: Bool = false) -> ApplicationUsageEvidence {
        .init(lastUsed: used.map { now.addingTimeInterval(-Double($0) * 86_400) },
              added: added.map { now.addingTimeInterval(-Double($0) * 86_400) }, running: running, background: background)
    }
    func testUserChosenThirtyDayThresholdAndBoundary() {
        XCTAssertEqual(ApplicationInsightPolicy.unusedDays, 30)
        XCTAssertTrue(ApplicationInsightPolicy.isUnused(evidence(used: 30), now: now))
        XCTAssertFalse(ApplicationInsightPolicy.isUnused(evidence(used: 29), now: now))
    }
    func testUnknownDatesNeverMeanUnusedAndRecentInstallIsExcluded() {
        XCTAssertFalse(ApplicationInsightPolicy.isUnused(evidence(used: nil), now: now))
        XCTAssertFalse(ApplicationInsightPolicy.isUnused(evidence(added: nil), now: now))
        XCTAssertFalse(ApplicationInsightPolicy.isUnused(evidence(added: 29), now: now))
        XCTAssertFalse(ApplicationInsightPolicy.isUnused(evidence(used: -2), now: now))
    }
    func testRunningAndBackgroundAppsAreExcluded() {
        XCTAssertFalse(ApplicationInsightPolicy.isUnused(evidence(running: true), now: now))
        XCTAssertFalse(ApplicationInsightPolicy.isUnused(evidence(background: true), now: now))
    }
    private func incompatible(_ arch: Set<String>?, minimum: String? = nil, perArch: [String: String] = [:], arm: Bool = true) -> String? {
        ApplicationInsightPolicy.incompatibility(architectures: arch, minimum: minimum, perArchitecture: perArch, system: "15.1", appleSilicon: arm)
    }
    func testIntelOnAppleSiliconIsNotAutomaticallyIncompatible() {
        XCTAssertNil(incompatible(["x86_64"], minimum: "13.0"))
        XCTAssertNotNil(incompatible(["i386", "ppc"]))
        XCTAssertNil(incompatible(nil))
        XCTAssertNil(incompatible([]))
        XCTAssertNotNil(incompatible(["arm64"], arm: false))
    }
    func testSystemVersionAndPerArchitectureFallbackAreConservative() {
        XCTAssertNotNil(incompatible(["arm64"], minimum: "16.0"))
        XCTAssertNil(incompatible(["arm64"], minimum: "15.1.0"))
        XCTAssertNil(incompatible(["arm64", "x86_64"], perArch: ["arm64": "16", "x86_64": "13"]))
        XCTAssertNil(incompatible(["arm64", "x86_64"], perArch: ["x86_64": "16"]))
        XCTAssertNil(incompatible(["arm64"], minimum: "unknown"))
    }
    @MainActor func testInstallerSelectionStartsEmptyAndEmptyRemovalDoesNothing() {
        let model = ApplicationsInsightsModel()
        XCTAssertTrue(model.selectedInstallers.isEmpty)
        model.trashSelectedInstallers()
        XCTAssertFalse(model.isRemoving)
        XCTAssertNil(model.removalMessage)
    }
    func testInstallerRuleAcceptsOnlyExplicitPackageExtensionsAndDoesNotSelectThem() throws {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("MacCareInstallersFixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for file in ["Example.dmg", "Example.pkg", "Personal.zip", "Partial.dmg.download"] {
            try Data([1, 2, 3]).write(to: root.appendingPathComponent(file))
        }
        let rule = """
        id = "downloads.installers"
        category = "downloads-installers"
        version = 1
        root = "\(root.path)"
        depth = "per-app"
        autoselect = false
        [[include]]
        kind = "name-suffix"
        ends_with = ".dmg"
        [[include]]
        kind = "name-suffix"
        ends_with = ".pkg"
        """
        let items = try Engine.scan(ruleTOML: rule)
        XCTAssertEqual(Set(items.map { $0.url.lastPathComponent }), ["Example.dmg", "Example.pkg"])
        XCTAssertTrue(items.allSatisfy { !$0.autoselect })
        let decisions = try Engine.planRemoval(.init(scope_root: root.path, items: items.map { .init(path: $0.path, identity: $0.identity) }, rule: rule))
        XCTAssertTrue(decisions.allSatisfy(\.allowed), "\(decisions)")
    }
}
