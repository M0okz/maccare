import XCTest
@testable import MacCare

final class MobileDeviceWiFiTests: XCTestCase {
    private let id = String(repeating: "a", count: 64)

    @MainActor
    func testRefreshOnlyReadsAndExplicitChangeTargetsOneDeviceThenVerifiesState() async throws {
        let runner = WiFiRunner(id: id)
        let model = MobileDeviceWiFiModel { await runner.run($0) }
        await model.refresh()
        let device = try XCTUnwrap(model.devices.first)
        XCTAssertEqual(device.wifiEnabled, true)
        var commands = await runner.commands
        XCTAssertEqual(commands, [["--list-wifi"]], "Opening the screen cannot enable Wi-Fi")
        await model.setWiFi(for: device, enabled: false)
        commands = await runner.commands
        XCTAssertEqual(commands, [["--list-wifi"], ["--set-wifi", id, "off"]])
        XCTAssertEqual(model.devices.first?.wifiEnabled, false)
        XCTAssertFalse(model.isError)
    }

    @MainActor
    func testReadbackMismatchCannotAnnounceSuccessfulConfiguration() async throws {
        let runner = WiFiRunner(id: id, refuseChange: true)
        let model = MobileDeviceWiFiModel { await runner.run($0) }
        await model.refresh()
        await model.setWiFi(for: try XCTUnwrap(model.devices.first), enabled: false)
        XCTAssertEqual(model.devices.first?.wifiEnabled, true)
        XCTAssertTrue(model.isError)
        XCTAssertTrue(model.message?.contains("n’a pas pu être confirmé") == true)
    }

    @MainActor
    func testDisconnectedOrUnlistedDeviceCannotIssueAWrite() async throws {
        let runner = WiFiRunner(id: id, usb: false)
        let model = MobileDeviceWiFiModel { await runner.run($0) }
        await model.refresh()
        await model.setWiFi(for: try XCTUnwrap(model.devices.first), enabled: false)
        let unknown = MobileDeviceWiFiModel.Device(id: String(repeating: "b", count: 64), name: "Autre iPhone",
                                                  wifiEnabled: true, usbConnected: true, canConfigure: true)
        await model.setWiFi(for: unknown, enabled: false)
        let commands = await runner.commands
        XCTAssertEqual(commands, [["--list-wifi"]])
    }

    func testMalformedFlagsAndTargetsAreRejectedAndUSBWinsDuplicateDiscovery() {
        let prefix = "{\"id\":\"\(id)\",\"name\":\"iPhone\",\"wifiEnabled\":true,"
        let wifi = prefix + "\"usbConnected\":false,\"canConfigure\":false}\n"
        let usb = prefix + "\"usbConnected\":true,\"canConfigure\":true}\n"
        let parsed = MobileDeviceWiFiModel.parse(Data((usb + wifi).utf8))
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.usbConnected, true)
        XCTAssertTrue(MobileDeviceWiFiModel.parse(Data(usb.replacingOccurrences(of: id, with: "../phone").utf8)).isEmpty)
        XCTAssertTrue(MobileDeviceWiFiModel.parse(Data(usb.replacingOccurrences(of: "\"wifiEnabled\":true", with: "\"wifiEnabled\":1").utf8)).isEmpty)
    }
}

private actor WiFiRunner {
    let id: String
    let refuseChange: Bool
    let usb: Bool
    var commands: [[String]] = []
    var enabled = true
    init(id: String, refuseChange: Bool = false, usb: Bool = true) { self.id = id; self.refuseChange = refuseChange; self.usb = usb }
    func run(_ arguments: [String]) -> MobileDeviceBatteryReader.Output {
        commands.append(arguments)
        if arguments.first == "--set-wifi" && !refuseChange { enabled = arguments.last == "on" }
        let record = "{\"id\":\"\(id)\",\"name\":\"iPhone\",\"wifiEnabled\":\(enabled),\"usbConnected\":\(usb),\"canConfigure\":\(usb)}\n{\"status\":\"complete\"}\n"
        return .init(data: Data(record.utf8), exitedNormally: true)
    }
}
