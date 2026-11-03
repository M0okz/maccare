import XCTest
@testable import MacCare

final class MacHardwarePresentationTests: XCTestCase {
    func testClassicThirteenInchM1AndM2NeverUseNotchedArtwork() {
        XCTAssertEqual(MacHardwarePresentation.resolve(identifier: "MacBookPro17,1").family, .pro13)
        XCTAssertEqual(MacHardwarePresentation.resolve(identifier: "Mac14,7").family, .pro13)
        XCTAssertTrue(MacHardwarePresentation.resolve(identifier: "MacBookPro17,1").title.contains("M1"))
    }
    func testDifferentHardwareFamiliesKeepDifferentSilhouettes() {
        XCTAssertEqual(MacHardwarePresentation.resolve(identifier: "MacBookPro18,3").family, .proNotched)
        XCTAssertEqual(MacHardwarePresentation.resolve(identifier: "MacBookAir10,1").family, .airClassic)
        XCTAssertEqual(MacHardwarePresentation.resolve(identifier: "Mac14,2").family, .airNotched)
        XCTAssertEqual(MacHardwarePresentation.resolve(identifier: "Macmini9,1").family, .mini)
    }
    func testUnknownIdentifiersDoNotInventARecognizedModel() {
        let unknown = MacHardwarePresentation.resolve(identifier: "Mac999,99")
        XCTAssertEqual(unknown.family, .desktop)
        XCTAssertEqual(unknown.title, "Mac")
        XCTAssertEqual(unknown.identifier, "Mac999,99")
    }
}
