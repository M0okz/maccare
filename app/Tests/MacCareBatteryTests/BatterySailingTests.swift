import Foundation
import Testing
import MacCareBattery

struct BatterySailingTests {
    @Test func startsPausedInsideBandThenCompletesAWholeRecharge() {
        var policy = BatteryProtectionPolicy()
        let configuration = BatteryConfiguration(limit: 80, thermalProtection: false, sailingWidth: 10)
        func snapshot(_ percent: Int) -> BatterySnapshot { .init(percent: percent, onAC: true, temperature: 25) }
        #expect(policy.evaluate(snapshot(77), configuration: configuration, topUp: false).suspend)
        #expect(policy.evaluate(snapshot(71), configuration: configuration, topUp: false).suspend)
        #expect(policy.evaluate(snapshot(70), configuration: configuration, topUp: false).suspend == false)
        #expect(policy.evaluate(snapshot(77), configuration: configuration, topUp: false).suspend == false)
        #expect(policy.evaluate(snapshot(80), configuration: configuration, topUp: false).suspend)
        #expect(policy.evaluate(snapshot(79), configuration: configuration, topUp: true).suspend == false)
    }
    @Test(arguments: [1, 21, -10, Int.max]) func rejectsInvalidBands(width: Int) {
        #expect(BatteryConfiguration(limit: 80, sailingWidth: width).isValid == false)
    }
    @Test func migratesExistingPreferencesAndKeepsNativeRestriction() throws {
        let value = try JSONDecoder().decode(BatteryConfiguration.self, from: Data(#"{"limit":80,"thermalProtection":false,"maximumTemperature":35}"#.utf8))
        #expect(value.sailingWidth == nil)
        #expect(value.resumeLimit == 77)
        #expect(BatteryControlCapabilities(backend: .nativeLimit).supportsSailing == false)
        #expect(BatteryControlCapabilities(backend: .firmware).supportsSailing)
    }
}
