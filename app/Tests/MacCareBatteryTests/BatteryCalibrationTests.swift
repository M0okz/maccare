import Foundation
import Testing
import MacCareBattery

struct BatteryCalibrationTests {
    @Test func fullCycleReleasesAdapterAtLowThresholdAndReturnsToConfiguredLimit() throws {
        var cycle = BatteryCycle.calibration(target: 80, now: 0)
        func snapshot(_ percent: Int, _ ac: Bool = true) -> BatterySnapshot { .init(percent: percent, onAC: ac, temperature: 28) }
        let first = try cycle.advance(snapshot: snapshot(80), now: 1)
        #expect(first.limit == 100 && first.discharge == false && first.finished == false)
        #expect(cycle.status.phase == .chargingToFull)
        #expect(try cycle.advance(snapshot: snapshot(100), now: 2).discharge)
        #expect(cycle.status.phase == .dischargingForCalibration)
        #expect(try cycle.advance(snapshot: snapshot(11, false), now: 3).discharge)
        #expect(try cycle.advance(snapshot: snapshot(10, false), now: 4).discharge == false)
        #expect(cycle.status.phase == .rechargingToFull)
        #expect(try cycle.advance(snapshot: snapshot(50), now: 5).limit == 100)
        #expect(try cycle.advance(snapshot: snapshot(100), now: 6).discharge)
        #expect(cycle.status.phase == .returningToLimit)
        #expect(try cycle.advance(snapshot: snapshot(81, false), now: 7).finished == false)
        let last = try cycle.advance(snapshot: snapshot(80, false), now: 8)
        #expect(last.discharge == false && last.limit == 80 && last.finished)
    }
    @Test func lowerThanPlannedMeasurementStillReconnectsAtLowPhase() throws {
        var cycle = BatteryCycle.calibration(target: 70, now: 0)
        _ = try cycle.advance(snapshot: .init(percent: 100, onAC: true, temperature: 28), now: 1)
        #expect(try cycle.advance(snapshot: .init(percent: 8, onAC: false, temperature: 28), now: 2).discharge == false)
    }
    @Test func chargerMustReappearAfterSwitchingBackToCharge() throws {
        var cycle = BatteryCycle.calibration(target: 80, now: 0)
        _ = try cycle.advance(snapshot: .init(percent: 100, onAC: true, temperature: 28), now: 1)
        _ = try cycle.advance(snapshot: .init(percent: 10, onAC: false, temperature: 28), now: 2)
        _ = try cycle.advance(snapshot: .init(percent: 10, onAC: false, temperature: 28), now: 10)
        #expect(throws: (any Error).self) { try cycle.advance(snapshot: .init(percent: 10, onAC: false, temperature: 28), now: 33) }
    }
    @Test func calibrationCannotContinueOnUnknownMeasurements() {
        var cycle = BatteryCycle.calibration(target: 80, now: 0)
        #expect(throws: (any Error).self) { try cycle.advance(snapshot: .init(percent: nil, onAC: true, temperature: 28), now: 1) }
    }
}
