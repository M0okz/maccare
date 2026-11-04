import Foundation
import IOKit
import Testing
@testable import MacCareBattery

struct BatteryNativeHardwareTests {
    private enum Failure: Error, Equatable { case read, mutation, smcRead }

    private final class Driver: NativeChargeDriver {
        var reading = NativeChargeReading(state: .init(enabled: false, limit: 100), supportedLimits: Array(80...100))
        var reads = 0
        var limits: [Int] = []
        var restores: [NativeChargeState] = []
        var failRead = false
        var failMutation = false
        var ignoreMutation = false
        func read() throws -> NativeChargeReading {
            reads += 1
            if failRead { throw Failure.read }
            return reading
        }
        func setLimit(_ limit: Int) throws {
            limits.append(limit)
            if failMutation { throw Failure.mutation }
            if !ignoreMutation { reading.state = .init(enabled: limit < 100, limit: limit) }
        }
        func restore(_ state: NativeChargeState) throws {
            restores.append(state)
            if failMutation { throw Failure.mutation }
            if !ignoreMutation { reading.state = state }
        }
    }

    private final class SMC: ChargeHardware {
        var failRead = false
        var readError: (any Error)?
        var value: UInt8 = 0
        var reads = 0
        var captures = 0
        var writes: [UInt8] = []
        var records: [BatteryRecoveryRecord] = []
        func readSwitch() throws -> UInt8 {
            reads += 1
            if let readError { throw readError }
            if failRead { throw Failure.smcRead }
            return value
        }
        func writeSwitch(_ value: UInt8) throws { writes.append(value); self.value = value }
        func captureRecovery() throws -> BatteryRecoveryRecord {
            captures += 1
            guard value == 0 else { throw Failure.smcRead }
            return .init(backend: .legacyPair, machineID: "host")
        }
        func restore(_ record: BatteryRecoveryRecord) throws { records.append(record); value = 0 }
    }

    private func native(_ driver: Driver, identity: String? = "host") -> NativeChargeHardware {
        .init(driver: driver, identity: { identity })
    }

    private final class Policy: ChargeHardware {
        var error: BatteryNativePolicyError?
        var reads = 0
        var restores: [BatteryRecoveryRecord] = []
        var capabilities: BatteryControlCapabilities { .init(backend: .nativePolicy) }
        func readSwitch() throws -> UInt8 {
            reads += 1
            if let error { throw error }
            return 0
        }
        func writeSwitch(_ value: UInt8) throws { throw Failure.mutation }
        func captureRecovery() throws -> BatteryRecoveryRecord {
            .init(backend: .nativePolicy, machineID: "host", nativePolicyPreferences: .init(featureState: .absent, limit: .absent))
        }
        func restore(_ record: BatteryRecoveryRecord) throws { restores.append(record) }
    }

    @Test func policyIsOnlyAllowedOnTheValidationModel() {
        #expect(AppleSiliconChargeHardware.nativePolicyValidated(model: "MacBookPro17,1"))
        for model: String? in ["MacBookAir10,1", "Mac16,12", "MacBookPro18,3", "", nil] {
            #expect(!AppleSiliconChargeHardware.nativePolicyValidated(model: model))
        }
    }
    @Test func discoveryDoesNotActivateThePolicyWithoutValidation() throws {
        let smc = SMC(), driver = Driver(), policy = Policy()
        smc.failRead = true
        let hardware = AppleSiliconChargeHardware(smc: smc, native: native(driver), nativePolicy: policy, nativeAvailable: true)
        #expect(try hardware.captureRecovery().backend == .nativeLimit)
        #expect(policy.reads == 0 && policy.restores.isEmpty)
        #expect(hardware.capabilities.supportsSailing == false)
        #expect(driver.limits.isEmpty && smc.writes.isEmpty)
    }

    @Test func ambiguousPolicyNeverFallsBackToAnotherNativeMethod() {
        let smc = SMC(), driver = Driver(), policy = Policy()
        smc.failRead = true; policy.error = .invalidState
        let hardware = AppleSiliconChargeHardware(smc: smc, native: native(driver), nativePolicy: policy,
            nativeAvailable: true, nativePolicyActivationAllowed: true)
        #expect(throws: BatteryNativePolicyError.self) { _ = try hardware.captureRecovery() }
        #expect(driver.reads == 0 && driver.limits.isEmpty)
        #expect(smc.writes.isEmpty)
    }

    @Test func unavailablePolicyAllowsReadOnlyFallbackButOlderOSNeverProbesIt() throws {
        let smc = SMC(), driver = Driver(), policy = Policy()
        smc.failRead = true; policy.error = .unavailable
        let oldOS = AppleSiliconChargeHardware(smc: smc, native: native(driver), nativePolicy: policy, nativeAvailable: false)
        #expect(throws: Failure.smcRead) { _ = try oldOS.readSwitch() }
        #expect(policy.reads == 0 && driver.reads == 0)
        let hardware = AppleSiliconChargeHardware(smc: smc, native: native(driver), nativePolicy: policy,
            nativeAvailable: true, nativePolicyActivationAllowed: true)
        #expect(try hardware.captureRecovery().backend == .nativeLimit)
        #expect(driver.limits.isEmpty && smc.writes.isEmpty)
    }

    @Test func policyCrashRecoveryDoesNotRediscoverSMCOrReadSliderBackend() throws {
        let smc = SMC(), driver = Driver(), policy = Policy()
        let hardware = AppleSiliconChargeHardware(smc: smc, native: native(driver), nativePolicy: policy, nativeAvailable: true)
        let record = try policy.captureRecovery()
        try hardware.restore(record)
        #expect(policy.restores == [record])
        #expect(smc.reads == 0 && driver.reads == 0)
        #expect(hardware.capabilities.backend == .nativePolicy)
    }

    @Test func malformedPolicyJournalNeverReachesAnyRestorationDriver() throws {
        let smc = SMC(), driver = Driver(), policy = Policy()
        let hardware = AppleSiliconChargeHardware(smc: smc, native: native(driver), nativePolicy: policy, nativeAvailable: true)
        let valid = try policy.captureRecovery()
        let encoded = try JSONEncoder().encode(valid)
        var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["version", "adapterBackend", "firmwareUpper"] {
            var invalid = json
            invalid[key] = key == "version" ? 3 : 1
            let record = try JSONDecoder().decode(BatteryRecoveryRecord.self, from: JSONSerialization.data(withJSONObject: invalid))
            #expect(!record.isValid)
            #expect(throws: BatteryHardwareError.self) { try hardware.restore(record) }
        }
        json["nativePolicyPreferences"] = nil
        let missing = try JSONDecoder().decode(BatteryRecoveryRecord.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(throws: BatteryHardwareError.self) { try hardware.restore(missing) }
        #expect(policy.restores.isEmpty && smc.records.isEmpty && driver.restores.isEmpty)
    }

    @Test func nativeFallbackReportsARealPermissionRefusalWithoutWriting() throws {
        let smc = SMC(), driver = Driver()
        smc.readError = BatteryHardwareError(code: kIOReturnNotPrivileged)
        let hardware = AppleSiliconChargeHardware(smc: smc, native: native(driver), nativeAvailable: true)
        #expect(hardware.capabilities.backend == .nativeLimit)
        #expect(hardware.capabilities.limitation == .hardwareAccessDenied)
        #expect(hardware.capabilities.supportedLimits == Array(80...100))
        #expect(hardware.capabilities.supportsSailing == false)
        #expect(driver.limits.isEmpty)
        #expect(smc.writes.isEmpty)
        smc.readError = nil
        #expect(hardware.capabilities.backend == .legacyPair)
        #expect(hardware.capabilities.limitation == nil)
    }

    @Test func aMissingSMCMethodIsNotReportedAsAPermissionRefusal() {
        let smc = SMC(), driver = Driver(); smc.failRead = true
        let hardware = AppleSiliconChargeHardware(smc: smc, native: native(driver), nativeAvailable: true)
        #expect(hardware.capabilities.backend == .nativeLimit)
        #expect(hardware.capabilities.limitation == nil)
        #expect(driver.limits.isEmpty)
    }

    @Test func olderCapabilityMessagesDecodeWithoutAnInventedRestriction() throws {
        let json = Data(#"{"backend":4,"supportedLimits":[80,100],"supportsThermalProtection":false}"#.utf8)
        let capabilities = try JSONDecoder().decode(BatteryControlCapabilities.self, from: json)
        #expect(capabilities.isValid)
        #expect(capabilities.limitation == nil)
    }

    @Test(arguments: Array(13...25))
    func olderMacOSVersionsNeverEnableNativeBackend(major: Int) {
        #expect(AppleSiliconChargeHardware.supportsNativeLimit(.init(majorVersion: major, minorVersion: 0, patchVersion: 0)) == false)
    }

    @Test(arguments: Array(0...3))
    func macOS26BeforePointFourDoesNotEnableNativeBackend(minor: Int) {
        #expect(AppleSiliconChargeHardware.supportsNativeLimit(.init(majorVersion: 26, minorVersion: minor, patchVersion: 9)) == false)
    }

    @Test(arguments: [
        OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0),
        .init(majorVersion: 26, minorVersion: 5, patchVersion: 0),
        .init(majorVersion: 27, minorVersion: 0, patchVersion: 0),
        .init(majorVersion: 28, minorVersion: 0, patchVersion: 0)
    ])
    func nativeEligibleVersionsStillRequireCapabilityDetection(version: OperatingSystemVersion) {
        #expect(AppleSiliconChargeHardware.supportsNativeLimit(version))
    }

    @Test func SMCDiscoveryIsReadOnlyAndCapturePreservesNativeCompanion() throws {
        let smc = SMC(), driver = Driver()
        let hardware = AppleSiliconChargeHardware(smc: smc, native: native(driver), nativeAvailable: true)
        #expect(try hardware.readSwitch() == 0)
        #expect(hardware.capabilities.backend == .legacyPair)
        #expect(driver.reads == 0)
        let record = try hardware.captureRecovery()
        #expect(record.backend == .legacyPair)
        #expect(record.nativeState == driver.reading.state)
        #expect(record.version == 3)
        #expect(driver.reads > 0)
        #expect(driver.limits.isEmpty)
    }

    @Test func unavailableNativeOSDoesNotReadOrMutateTheNativeDriver() {
        let smc = SMC(), driver = Driver()
        smc.failRead = true
        let hardware = AppleSiliconChargeHardware(smc: smc, native: native(driver), nativeAvailable: false)
        #expect(throws: Failure.smcRead) { _ = try hardware.readSwitch() }
        #expect(driver.reads == 0)
        #expect(driver.limits.isEmpty)
        #expect(driver.restores.isEmpty)
    }

    @Test func alreadyControlledSMCDoesNotFallBackToNativeAfterCaptureRefusal() {
        let smc = SMC(), driver = Driver()
        smc.value = 2
        let hardware = AppleSiliconChargeHardware(smc: smc, native: native(driver), nativeAvailable: true)
        #expect(throws: Failure.smcRead) { _ = try hardware.captureRecovery() }
        #expect(smc.captures == 1)
        #expect(driver.reads == 0)
    }

    @Test func nativeCaptureAndPreparationOnlyReadAndPreserveOriginalLimit() throws {
        let driver = Driver()
        driver.reading.state = .init(enabled: true, limit: 85)
        let hardware = native(driver)
        #expect(try hardware.readSwitch() == 2)
        let record = try hardware.captureRecovery()
        try hardware.prepareForControl()
        #expect(record.backend == .nativeLimit)
        #expect(record.nativeState == .init(enabled: true, limit: 85))
        #expect(record.machineID == "host")
        #expect(record.isValid)
        #expect(driver.limits.isEmpty)
        #expect(driver.restores.isEmpty)
    }

    @Test(arguments: [true, nil] as [Bool?])
    func unknownOrActiveCalibrationBlocksCapture(calibrationOverride: Bool?) {
        let driver = Driver()
        driver.reading.calibrationOverride = calibrationOverride
        #expect(throws: NativeChargeError.self) { _ = try native(driver).captureRecovery() }
        #expect(driver.limits.isEmpty)
        #expect(driver.restores.isEmpty)
    }

    @Test(arguments: [NativeChargeState(enabled: true, limit: 100), .init(enabled: false, limit: 85)])
    func nonRestorableNativeStateCannotBeCaptured(state: NativeChargeState) {
        let driver = Driver()
        driver.reading.state = state
        #expect(throws: NativeChargeError.self) { _ = try native(driver).captureRecovery() }
        #expect(driver.limits.isEmpty)
    }

    @Test func missingMachineIdentityBlocksCaptureBeforeReadingTheDriver() {
        let driver = Driver()
        #expect(throws: BatteryHardwareError.self) { _ = try native(driver, identity: nil).captureRecovery() }
        #expect(driver.reads == 0)
        #expect(driver.limits.isEmpty)
    }

    @Test(arguments: [
        NativeChargeReading(state: .init(enabled: true, limit: 79), supportedLimits: Array(80...100)),
        .init(state: .init(enabled: false, limit: 101), supportedLimits: Array(80...100)),
        .init(state: .init(enabled: false, limit: 100), supportedLimits: []),
        .init(state: .init(enabled: false, limit: 100), supportedLimits: [80, 80, 100]),
        .init(state: .init(enabled: false, limit: 100), supportedLimits: [100, 80]),
        .init(state: .init(enabled: true, limit: 80), supportedLimits: [80, 85]),
        .init(state: .init(enabled: true, limit: 85), supportedLimits: [80, 100])
    ])
    func invalidNativeReadCannotCaptureOrMutate(reading: NativeChargeReading) {
        let driver = Driver()
        driver.reading = reading
        let hardware = native(driver)
        #expect(throws: NativeChargeError.self) { _ = try hardware.readSwitch() }
        #expect(throws: NativeChargeError.self) { _ = try hardware.captureRecovery() }
        #expect(hardware.capabilities.supportedLimits.isEmpty)
        #expect(driver.limits.isEmpty)
        #expect(driver.restores.isEmpty)
    }

    @Test(arguments: [79, 101])
    func outOfRangeSetpointNeverReachesNativeDriver(limit: Int) throws {
        let driver = Driver(), hardware = native(driver)
        _ = try hardware.captureRecovery()
        #expect(throws: NativeChargeError.self) { try hardware.setChargeLimit(limit) }
        #expect(driver.limits.isEmpty)
    }

    @Test func freshCapabilitiesMustStillSupportRequestedLimitBeforeMutation() throws {
        let driver = Driver(), hardware = native(driver)
        _ = try hardware.captureRecovery()
        driver.reading.supportedLimits = [90, 95, 100]
        #expect(throws: NativeChargeError.self) { try hardware.setChargeLimit(80) }
        #expect(driver.limits.isEmpty)
    }

    @Test func freshCapabilitiesMustSupportOriginalLimitBeforeRestoration() throws {
        let driver = Driver(), hardware = native(driver)
        driver.reading.state = .init(enabled: true, limit: 85)
        let record = try hardware.captureRecovery()
        try hardware.setChargeLimit(80)
        driver.reading.supportedLimits = [80, 100]
        #expect(throws: NativeChargeError.self) { try hardware.restore(record) }
        #expect(driver.restores.isEmpty)
    }

    @Test func foreignMachineRecordCannotReadOrMutateNativeDriver() {
        let driver = Driver(), hardware = native(driver)
        let record = BatteryRecoveryRecord(backend: .nativeLimit, machineID: "another-host", nativeState: .init(enabled: true, limit: 85))
        #expect(throws: BatteryHardwareError.self) { try hardware.restore(record) }
        #expect(driver.reads == 0)
        #expect(driver.restores.isEmpty)
    }

    @Test(arguments: [NativeChargeState(enabled: false, limit: 85), .init(enabled: true, limit: 100)])
    func incoherentRecoveryRecordCannotReachDriver(state: NativeChargeState) {
        let driver = Driver(), hardware = native(driver)
        let record = BatteryRecoveryRecord(backend: .nativeLimit, machineID: "host", nativeState: state)
        #expect(record.isValid == false)
        #expect(throws: BatteryHardwareError.self) { try hardware.restore(record) }
        #expect(driver.reads == 0)
        #expect(driver.restores.isEmpty)
    }

    @Test func unchangedLimitsAndRepeatedRestorationDoNotRewriteNativeState() throws {
        let driver = Driver(), hardware = native(driver)
        let record = try hardware.captureRecovery()
        try hardware.setChargeLimit(80)
        try hardware.setChargeLimit(80)
        #expect(driver.limits == [80])
        try hardware.restore(record)
        try hardware.restore(record)
        #expect(driver.restores == [.init(enabled: false, limit: 100)])
        #expect(try hardware.readSwitch() == 0)
    }

    @Test func missingReadbackConfirmationIsAnErrorInsteadOfOptimisticSuccess() throws {
        let driver = Driver(), hardware = native(driver)
        _ = try hardware.captureRecovery()
        driver.ignoreMutation = true
        #expect(throws: NativeChargeError.self) { try hardware.setChargeLimit(80) }
        #expect(driver.limits == [80])
    }

    @Test(arguments: [true, nil] as [Bool?])
    func calibrationBeginningAfterCaptureBlocksFurtherMutation(calibrationOverride: Bool?) throws {
        let driver = Driver(), hardware = native(driver)
        let record = try hardware.captureRecovery()
        try hardware.setChargeLimit(80)
        driver.reading.calibrationOverride = calibrationOverride
        #expect(throws: NativeChargeError.self) { try hardware.setChargeLimit(85) }
        #expect(throws: NativeChargeError.self) { try hardware.restore(record) }
        #expect(driver.limits == [80])
        #expect(driver.restores.isEmpty)
    }

    @Test func mutationFailureCannotSwitchFromPinnedNativeToRepairedSMC() throws {
        let smc = SMC(), driver = Driver()
        smc.failRead = true
        let hardware = AppleSiliconChargeHardware(smc: smc, native: native(driver), nativeAvailable: true)
        let record = try hardware.captureRecovery()
        let discoveryReads = smc.reads
        smc.failRead = false
        driver.failMutation = true
        #expect(throws: Failure.mutation) { try hardware.setChargeLimit(80) }
        #expect(hardware.capabilities.backend == .nativeLimit)
        #expect(smc.reads == discoveryReads)
        #expect(smc.writes.isEmpty)
        driver.failMutation = false
        try hardware.restore(record)
        #expect(hardware.capabilities.backend == .nativeLimit)
        #expect(smc.reads == discoveryReads)
    }

    @Test func failedFreshReadDoesNotAttemptANativeMutation() throws {
        let driver = Driver(), hardware = native(driver)
        let record = try hardware.captureRecovery()
        driver.failRead = true
        #expect(throws: Failure.read) { try hardware.setChargeLimit(80) }
        #expect(throws: Failure.read) { try hardware.restore(record) }
        #expect(driver.limits.isEmpty)
        #expect(driver.restores.isEmpty)
    }

    @Test func pinnedNativeSessionRejectsADifferentRestorationBackend() throws {
        let smc = SMC(), driver = Driver()
        smc.failRead = true
        let hardware = AppleSiliconChargeHardware(smc: smc, native: native(driver), nativeAvailable: true)
        _ = try hardware.captureRecovery()
        #expect(throws: BatteryHardwareError.self) { try hardware.restore(.init(backend: .legacyPair, machineID: "host")) }
        #expect(smc.records.isEmpty)
        #expect(driver.restores.isEmpty)
        #expect(hardware.capabilities.backend == .nativeLimit)
    }

    @Test func crashRestorationSelectsRecordedBackendInsteadOfRediscoveringSMC() throws {
        let smc = SMC(), driver = Driver()
        driver.reading.state = .init(enabled: true, limit: 80)
        let hardware = AppleSiliconChargeHardware(smc: smc, native: native(driver), nativeAvailable: true)
        let record = BatteryRecoveryRecord(backend: .nativeLimit, machineID: "host", nativeState: .init(enabled: true, limit: 85))
        try hardware.restore(record)
        #expect(driver.reading.state == .init(enabled: true, limit: 85))
        #expect(hardware.capabilities.backend == .nativeLimit)
        #expect(smc.reads == 0)
        hardware.endSession()
        #expect(hardware.capabilities.backend == .legacyPair)
    }

    @Test func sleepRestorationKeepsNativeBackendPinnedForFreshHeartbeat() throws {
        let smc = SMC(), driver = Driver()
        smc.failRead = true
        let hardware = AppleSiliconChargeHardware(smc: smc, native: native(driver), nativeAvailable: true)
        let controller = BatteryProtectionController(hardware: hardware, markRecovery: { _ in }, clearRecovery: {})
        let session = UUID(), configuration = BatteryConfiguration(thermalProtection: false)
        let snapshot = BatterySnapshot(percent: 80, onAC: true, temperature: 30)
        try #require(controller.execute(.enable, configuration: configuration, uid: 501, sessionID: session, snapshot: snapshot, now: 0).active)
        let discoveryReads = smc.reads
        try controller.prepareForSleep()
        #expect(driver.reading.state == .init(enabled: false, limit: 100))
        smc.failRead = false
        controller.didWake(now: 1_000)
        _ = controller.tick(snapshot: snapshot, now: 1_001)
        #expect(driver.limits == [80])
        try #require(controller.execute(.heartbeat, configuration: nil, uid: 501, sessionID: session, snapshot: snapshot, now: 1_002).active)
        #expect(driver.limits == [80, 80])
        #expect(driver.reading.state == .init(enabled: true, limit: 80))
        #expect(smc.reads == discoveryReads)
        #expect(smc.writes.isEmpty)
    }
}
