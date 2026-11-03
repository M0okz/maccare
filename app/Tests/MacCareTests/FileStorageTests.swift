import XCTest
@testable import MacCare

final class FileStorageTests: XCTestCase {
    private func withDefaults(_ test: (UserDefaults) -> Void) {
        let suite = "MacCare-QA-FileStorage-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        test(defaults)
    }

    func testDefaultSearchesAndFiltersPreserveExistingBehavior() {
        withDefaults { defaults in
            let p = FileStoragePreferences(defaults: defaults)
            XCTAssertTrue(p.searchLarge)
            XCTAssertTrue(p.searchDuplicates)
            XCTAssertEqual(p.minSize, .mb100)
            XCTAssertEqual(p.age, .any)
            XCTAssertEqual(p.spaceView, .map)
            XCTAssertEqual(p.spaceStart, .startupDisk)
        }
    }

    func testExplicitlyDisabledSearchesDoNotRevertToDefaults() {
        withDefaults { defaults in
            defaults.set(false, forKey: FileStoragePreferences.Key.large)
            defaults.set(false, forKey: FileStoragePreferences.Key.duplicates)
            XCTAssertFalse(FileStoragePreferences(defaults: defaults).hasSearch)
        }
    }

    func testFiltersAndExplorerChoiceArePersistedSeparately() {
        withDefaults { defaults in
            defaults.set(Int(LargeFilesModel.MinSize.gb1.rawValue), forKey: FileStoragePreferences.Key.minSize)
            defaults.set(LargeFilesModel.Age.year1.rawValue, forKey: FileStoragePreferences.Key.age)
            defaults.set("list", forKey: FileStoragePreferences.Key.view)
            defaults.set("documents", forKey: FileStoragePreferences.Key.start)
            let p = FileStoragePreferences(defaults: defaults)
            XCTAssertEqual(p.minSize, .gb1)
            XCTAssertEqual(p.age, .year1)
            XCTAssertEqual(p.spaceView, .list)
            XCTAssertEqual(p.spaceStart, .documents)
        }
    }

    func testInvalidStoredValuesFallBackToSupportedOptions() {
        withDefaults { defaults in
            defaults.set(-1, forKey: FileStoragePreferences.Key.minSize)
            defaults.set(123, forKey: FileStoragePreferences.Key.age)
            defaults.set("unknown", forKey: FileStoragePreferences.Key.view)
            defaults.set("/arbitrary/path", forKey: FileStoragePreferences.Key.start)
            let p = FileStoragePreferences(defaults: defaults)
            XCTAssertEqual(p.minSize, .mb100)
            XCTAssertEqual(p.age, .any)
            XCTAssertEqual(p.spaceView, .map)
            XCTAssertEqual(p.spaceStart, .startupDisk)
        }
    }

    func testFilesAndExplorerHaveIndependentRoutes() {
        XCTAssertEqual(NavigationSection.files.defaultDestination, .filesOverview)
        XCTAssertEqual(Set(NavigationSection.files.destinations), [.filesOverview, .largeFiles, .duplicates])
        XCTAssertEqual(NavigationSection.space.destinations, [.space])
        var history = NavigationHistory()
        history.remember(.duplicates)
        XCTAssertEqual(history.destination(for: .files, developerTools: true), .duplicates)
        XCTAssertEqual(history.destination(for: .space, developerTools: true), .space)
        XCTAssertTrue(SettingsTab.allCases.contains(.filesStorage))
    }
    func testDisabledSearchesNeverLaunchEngineWork() async {
        await MainActor.run {
            withDefaults { defaults in
                defaults.set(false, forKey: FileStoragePreferences.Key.large)
                defaults.set(false, forKey: FileStoragePreferences.Key.duplicates)
                let large = LargeFilesModel(), duplicates = DuplicatesModel()
                let analysis = FilesAnalysisModel()
                analysis.analyze(large: large, duplicates: duplicates, preferences: FileStoragePreferences(defaults: defaults))
                XCTAssertFalse(analysis.hasStarted)
                XCTAssertEqual(large.stage, .idle)
                XCTAssertEqual(duplicates.stage, .idle)
            }
        }
    }

    func testInitialFiltersAreAppliedToLargeFileResults() async {
        await MainActor.run {
            withDefaults { defaults in
                defaults.set(Int(LargeFilesModel.MinSize.gb1.rawValue), forKey: FileStoragePreferences.Key.minSize)
                defaults.set(LargeFilesModel.Age.months6.rawValue, forKey: FileStoragePreferences.Key.age)
                let model = LargeFilesModel()
                model.applyDefaultFilters(FileStoragePreferences(defaults: defaults))
                XCTAssertEqual(model.minSize, .gb1)
                XCTAssertEqual(model.age, .months6)
            }
        }
    }

    func testExplorerStartsAtConfiguredSupportedFolder() async {
        await MainActor.run {
            withDefaults { defaults in
                defaults.set("documents", forKey: FileStoragePreferences.Key.start)
                let model = SpaceModel(preferences: FileStoragePreferences(defaults: defaults))
                XCTAssertEqual(model.root.path, SpaceStartFolder.documents.path)
                XCTAssertEqual(model.currentPath, model.root.path)
            }
        }
    }

}
