import AppKit
import XCTest
@testable import MacCare

final class TrayProcessIconTests: XCTestCase {
    func testOwningApplicationIsTheOutermostAppIncludingTranslocatedAndUnicodePaths() {
        let pairs = [
            ("/Applications/Helium.app/Contents/Frameworks/Helium Framework.framework/Versions/156/Helpers/Helium Helper (Renderer).app/Contents/MacOS/Helium Helper", "/Applications/Helium.app"),
            ("/private/var/folders/uuid/AppTranslocation/id/d/Hélium Browser.app/Contents/Helpers/Helper.app/Contents/MacOS/Helper", "/private/var/folders/uuid/AppTranslocation/id/d/Hélium Browser.app"),
            ("/Applications/Browser.APP/Contents/MacOS/Browser", "/Applications/Browser.APP")
        ]
        for (executable, expected) in pairs {
            XCTAssertEqual(TrayProcessIconResolver.owningApplication(in: executable)?.path, expected)
        }
        for path in ["", "relative/Browser.app/Contents/MacOS/Browser", "/usr/libexec/service", "/tmp/Fake.application/service", "/tmp/Browser.app.backup/tool"] {
            XCTAssertNil(TrayProcessIconResolver.owningApplication(in: path))
        }
    }

    @MainActor
    func testHelperUsesItsOwningAppInsteadOfItsOwnRegisteredIcon() {
        let ownerIcon = NSImage(size: NSSize(width: 32, height: 32))
        let helperIcon = NSImage(size: NSSize(width: 16, height: 16))
        var requested: [URL] = []
        let resolver = TrayProcessIconResolver { url in requested.append(url); return ownerIcon }
        let icon = resolver.icon(executable: "/Applications/Helium.app/Contents/Helpers/Helium Helper.app/Contents/MacOS/Helper",
                                 registeredBundleURL: URL(fileURLWithPath: "/Applications/Helium.app/Contents/Helpers/Helium Helper.app"),
                                 registeredIcon: helperIcon)
        XCTAssertTrue(icon === ownerIcon)
        XCTAssertEqual(requested.map(\.path), ["/Applications/Helium.app"])
    }

    @MainActor
    func testNativeAppIconIsKeptAndBundleIconFillsAnAbsentNativeIcon() {
        let native = NSImage(size: NSSize(width: 32, height: 32))
        let disk = NSImage(size: NSSize(width: 16, height: 16))
        var reads = 0
        let resolver = TrayProcessIconResolver { _ in reads += 1; return disk }
        let app = URL(fileURLWithPath: "/Applications/Browser.app")
        XCTAssertTrue(resolver.icon(executable: app.path + "/Contents/MacOS/Browser", registeredBundleURL: app, registeredIcon: native) === native)
        XCTAssertEqual(reads, 0)
        XCTAssertTrue(resolver.icon(executable: app.path + "/Contents/MacOS/Browser", registeredBundleURL: app, registeredIcon: nil) === disk)
        XCTAssertEqual(reads, 1)
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        XCTAssertTrue(resolver.icon(executable: finder.path + "/Contents/MacOS/Finder", registeredBundleURL: finder, registeredIcon: native) === native)
    }

    @MainActor
    func testSystemServicesAndUnknownProcessesKeepTheGenericFallback() {
        let native = NSImage(size: NSSize(width: 32, height: 32))
        var reads = 0
        let resolver = TrayProcessIconResolver { _ in reads += 1; return native }
        for path in ["/System/Library/Frameworks/VideoToolbox.framework/XPCServices/VTDecoderXPCService.xpc/Contents/MacOS/VTDecoderXPCService", "/usr/libexec/service", "/bin/service"] {
            XCTAssertNil(resolver.icon(executable: path, registeredBundleURL: URL(fileURLWithPath: "/Applications/Other.app"), registeredIcon: native))
        }
        XCTAssertNil(resolver.icon(executable: "/tmp/tool", registeredBundleURL: URL(fileURLWithPath: "/Library/Services/Example.xpc"), registeredIcon: native))
        XCTAssertNil(resolver.icon(executable: "", registeredBundleURL: nil, registeredIcon: nil))
        XCTAssertEqual(reads, 0)
    }

    @MainActor
    func testRegisteredBundleCanIdentifyTheOwnerWhenTheExecutablePathIsUnavailable() {
        let owner = NSImage(size: NSSize(width: 32, height: 32))
        var requested: [String] = []
        let resolver = TrayProcessIconResolver { url in requested.append(url.path); return owner }
        XCTAssertTrue(resolver.icon(executable: "", registeredBundleURL: URL(fileURLWithPath: "/Applications/Browser.app/Contents/Helpers/Helper.app"), registeredIcon: nil) === owner)
        XCTAssertEqual(requested, ["/Applications/Browser.app"])
        let unavailable = TrayProcessIconResolver { _ in nil }
        XCTAssertNil(unavailable.icon(executable: "/missing/Browser.app/Contents/MacOS/Helper", registeredBundleURL: nil, registeredIcon: nil))
    }
}
