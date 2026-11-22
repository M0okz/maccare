import XCTest
import MacCareHelperProtocol

final class FanBoostSessionTests: XCTestCase {
    private final class Hardware: FanBoostHardware {
        var modes = [true, true]
        var thermal = true
        var responding = true
        var rejected: Int?
        var unwritten: Int?
        var blockedRestore: Int?
        var boosts: [Int] = []
        var replacing: [Bool] = []
        var restored: [Int] = []
        var marker: UInt8 = 0
        func automaticModes() throws -> [Bool] { modes }
        func thermalsAllowBoost() -> Bool { thermal }
        func fansResponding(mask: UInt8) -> Bool { responding }
        func boost(fan: Int, maximum: Bool, replacingBoost: Bool) -> (success: Bool, attempted: Bool) {
            boosts.append(fan)
            replacing.append(replacingBoost)
            return (fan != rejected && fan != unwritten, fan != unwritten)
        }
        func restore(fan: Int) -> Bool { restored.append(fan); return fan != blockedRestore }
        func record(mask: UInt8) throws { marker = mask }
    }

    func testPartialWriteRollsBackAndFailedRestorationIsRetried() throws {
        let hardware = Hardware()
        hardware.rejected = 1
        hardware.blockedRestore = 1
        let session = FanBoostSession(hardware: hardware, recoveryMask: 0)
        XCTAssertThrowsError(try session.apply(.maximum, now: .now))
        XCTAssertEqual(hardware.restored, [0, 1])
        XCTAssertEqual(hardware.marker, 2)
        hardware.blockedRestore = nil
        try session.check(now: .now)
        XCTAssertEqual(hardware.marker, 0)
    }

    func testExternalManualModeIsRespectedEvenIfItChangesDuringTakeover() {
        let hardware = Hardware()
        let session = FanBoostSession(hardware: hardware, recoveryMask: 0)
        hardware.modes = [true, false]
        XCTAssertThrowsError(try session.apply(.cool, now: .now))
        XCTAssertTrue(hardware.boosts.isEmpty)
        hardware.modes = [true, true]
        hardware.unwritten = 1
        XCTAssertThrowsError(try session.apply(.cool, now: .now))
        XCTAssertEqual(hardware.restored, [0])
    }

    func testTimeLimitSleepHeatAndStoppedFanAllRestoreAutomatic() throws {
        let start = Date()
        for cause in ["expiry", "wake", "heat", "stalled"] {
            let hardware = Hardware()
            let session = FanBoostSession(hardware: hardware, recoveryMask: 0)
            try session.apply(.cool, now: start)
            for tick in 1...150 {
                if cause == "heat" { hardware.thermal = false }
                if cause == "stalled" { hardware.responding = false }
                let elapsed = cause == "wake" ? 10 : tick * 2
                try session.check(now: start.addingTimeInterval(Double(elapsed)))
                if session.mask == 0 {
                    if cause == "expiry" { XCTAssertEqual(elapsed, 300) }
                    if cause == "stalled" { XCTAssertEqual(elapsed, 16) }
                    break
                }
            }
            XCTAssertEqual(hardware.marker, 0)
            XCTAssertEqual(hardware.restored, [0, 1])
        }
    }

    func testRestartAndExplicitAutoRestoreOnlyOwnedFans() throws {
        let hardware = Hardware()
        let session = FanBoostSession(hardware: hardware, recoveryMask: 2)
        try session.check(now: .now)
        XCTAssertEqual(hardware.restored, [1])
        try session.apply(.maximum, now: .now)
        try session.apply(.cool, now: .now)
        XCTAssertEqual(hardware.replacing, [false, false, true, true])
        try session.apply(.automatic, now: .now)
        XCTAssertEqual(hardware.restored, [1, 0, 1, 0, 1])
    }
}
