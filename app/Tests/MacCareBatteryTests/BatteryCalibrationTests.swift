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
        _ = try cycle.advance(snapshot: .init(percent: 10, onAC: false, temperature: 28), now: 122)
        #expect(throws: (any Error).self) { try cycle.advance(snapshot: .init(percent: 10, onAC: false, temperature: 28), now: 183) }
    }
    @Test func systemPostDischargeDelayDoesNotAbortCalibrationBeforePowerReturns() throws {
        var cycle = BatteryCycle.calibration(target: 80, now: 0)
        _ = try cycle.advance(snapshot: .init(percent: 100, onAC: true, temperature: 28), now: 1)
        _ = try cycle.advance(snapshot: .init(percent: 10, onAC: false, temperature: 28), now: 2)
        #expect(try cycle.advance(snapshot: .init(percent: 10, onAC: false, temperature: 28), now: 121).discharge == false)
        #expect(try cycle.advance(snapshot: .init(percent: 11, onAC: true, temperature: 28), now: 130).limit == 100)
        #expect(cycle.status.phase == .rechargingToFull)
    }
    @Test func aCalibrationAtRestIsNotStoppedByItsDuration() throws {
        func snapshot(_ percent: Int, _ ac: Bool = true) -> BatterySnapshot { .init(percent: percent, onAC: ac, temperature: 28) }
        let hour: TimeInterval = 3600
        var cycle = BatteryCycle.calibration(target: 80, now: 0)
        _ = try cycle.advance(snapshot: snapshot(100), now: 3 * hour)
        #expect(cycle.status.phase == .dischargingForCalibration)
        #expect(try cycle.advance(snapshot: snapshot(50, false), now: 15 * hour).discharge)
        #expect(try cycle.advance(snapshot: snapshot(11, false), now: 22 * hour).discharge)
        _ = try cycle.advance(snapshot: snapshot(10, false), now: 23 * hour)
        #expect(cycle.status.phase == .rechargingToFull)
        _ = try cycle.advance(snapshot: snapshot(100), now: 26 * hour)
        #expect(cycle.status.phase == .returningToLimit)
        #expect(try cycle.advance(snapshot: snapshot(80, false), now: 30 * hour).finished)
    }
    @Test func aPhaseThatMakesNoProgressStillEnds() throws {
        func snapshot(_ percent: Int, _ ac: Bool = true) -> BatterySnapshot { .init(percent: percent, onAC: ac, temperature: 28) }
        var charging = BatteryCycle.calibration(target: 80, now: 0)
        #expect(throws: (any Error).self) { try charging.advance(snapshot: snapshot(90), now: BatteryCycle.chargePhaseLimit) }
        var draining = BatteryCycle.calibration(target: 80, now: 0)
        _ = try draining.advance(snapshot: snapshot(100), now: 1)
        #expect(throws: (any Error).self) { try draining.advance(snapshot: snapshot(50, false), now: 1 + BatteryCycle.dischargePhaseLimit) }
        var long = BatteryCycle.calibration(target: 80, now: 0)
        _ = try long.advance(snapshot: snapshot(100), now: 11 * 3600)
        _ = try long.advance(snapshot: snapshot(10, false), now: 46 * 3600)
        _ = try long.advance(snapshot: snapshot(100), now: 57 * 3600)
        #expect(throws: (any Error).self) { try long.advance(snapshot: snapshot(90, false), now: BatteryCycle.cycleLimit) }
    }
    @Test func calibrationCannotContinueOnUnknownMeasurements() {
        var cycle = BatteryCycle.calibration(target: 80, now: 0)
        #expect(throws: (any Error).self) { try cycle.advance(snapshot: .init(percent: nil, onAC: true, temperature: 28), now: 1) }
    }
    @Test func roundedFullPercentageDoesNotInterruptEitherChargingPhase() throws {
        var cycle = BatteryCycle.calibration(target: 80, now: 0)
        let stillCharging = BatterySnapshot(percent: 100, onAC: true, charging: true, temperature: 28)
        let full = BatterySnapshot(percent: 100, onAC: true, charging: false, temperature: 28)
        #expect(try cycle.advance(snapshot: stillCharging, now: 1).discharge == false)
        #expect(cycle.status.phase == .chargingToFull)
        _ = try cycle.advance(snapshot: full, now: 2)
        _ = try cycle.advance(snapshot: .init(percent: 10, onAC: false, temperature: 28), now: 3)
        #expect(try cycle.advance(snapshot: stillCharging, now: 4).discharge == false)
        #expect(cycle.status.phase == .rechargingToFull)
        #expect(try cycle.advance(snapshot: full, now: 5).discharge)
        #expect(cycle.status.phase == .returningToLimit)
    }
    @Test func aFullChargeTargetFinishesWithoutAnotherAdapterIsolation() throws {
        var cycle = BatteryCycle.calibration(target: 100, now: 0)
        _ = try cycle.advance(snapshot: .init(percent: 100, onAC: true, temperature: 28), now: 1)
        _ = try cycle.advance(snapshot: .init(percent: 10, onAC: false, temperature: 28), now: 2)
        let last = try cycle.advance(snapshot: .init(percent: 100, onAC: true, temperature: 28), now: 3)
        #expect(last.finished)
        #expect(last.limit == 100)
        #expect(last.discharge == false)
    }
}
