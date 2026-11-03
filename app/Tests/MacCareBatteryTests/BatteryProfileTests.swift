import Testing
import MacCareBattery

struct BatteryProfileTests {
    @Test func profilesDoNotSilentlyReplaceAnUnsupportedLowerLimit() {
        let profile = BatteryProfile.presets[0]
        #expect(profile.configuration.limit == 70)
        #expect(profile.unavailableReason(for: .init(backend: .nativeLimit)) != nil)
        #expect(profile.unavailableReason(for: .init(backend: .chargeGate)) == nil)
        #expect(BatteryProfile.presets.allSatisfy { $0.isValid })
    }
}
