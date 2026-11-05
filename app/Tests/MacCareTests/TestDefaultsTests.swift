import XCTest

final class TestDefaultsTests: XCTestCase {
    func testPreferencesPersistOutsideTheUserPreferencesFolder() throws {
        let suite = testPreferencesSuite("TestDefaultsTests")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(42, forKey: "value")
        defaults.synchronize()

        XCTAssertEqual(UserDefaults(suiteName: suite)?.integer(forKey: "value"), 42)
        XCTAssertTrue(suite.hasPrefix(FileManager.default.temporaryDirectory.path))
    }
}
