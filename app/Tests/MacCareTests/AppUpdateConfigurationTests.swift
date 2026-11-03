import XCTest
@testable import MacCare

final class AppUpdateConfigurationTests: XCTestCase {
    private let key = Data(repeating: 7, count: 32).base64EncodedString()

    func testDevelopmentBuildWithoutAFeedDoesNotEnableTheUpdater() {
        XCTAssertNil(AppUpdateConfiguration(info: [:]))
        XCTAssertNil(AppUpdateConfiguration(info: ["SUFeedURL": "https://github.com/M0okz/maccare/releases/latest/download/appcast.xml"]))
    }

    func testPublicHTTPSFeedNeedsARealEd25519PublicKey() {
        let url = "https://github.com/M0okz/maccare/releases/latest/download/appcast.xml"
        let configuration = AppUpdateConfiguration(info: ["SUFeedURL": url, "SUPublicEDKey": key])
        XCTAssertEqual(configuration?.feedURL.absoluteString, url)
        XCTAssertEqual(configuration?.publicKey.count, 32)
        for invalidKey in ["", "not-base64", Data(repeating: 1, count: 64).base64EncodedString()] {
            XCTAssertNil(AppUpdateConfiguration(info: ["SUFeedURL": url, "SUPublicEDKey": invalidKey]))
        }
    }

    func testFeedNeverEmbedsCredentialsOrTokensAndRequiresHTTPS() {
        for url in ["http://github.com/feed.xml", "file:///tmp/feed.xml", "https://user:password@github.com/feed.xml",
                    "https://github.com/feed.xml?token=demo", "https://github.com/feed.xml#demo", "https://"] {
            XCTAssertNil(AppUpdateConfiguration(info: ["SUFeedURL": url, "SUPublicEDKey": key]), url)
        }
    }
}
