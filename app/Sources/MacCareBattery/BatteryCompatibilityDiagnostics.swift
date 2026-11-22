import Foundation
import CMacCarePowerUI
import Darwin

/// Read-only compatibility evidence. Contains a model identifier, never a serial
/// number, recovery identity, preference write, or probe by activation.
public struct BatteryCompatibilityDiagnostics: Codable, Sendable {
    public enum FullChargeOverride: String, Codable, Sendable {
        case inactive, active, unknown
        public static func read() -> Self { from(maccare_powerui_calibration_override()) }
        static func from(_ value: Int32) -> Self { value < 0 ? .unknown : (value == 0 ? .inactive : .active) }
    }
    public let model: String?
    public let effectiveUID: UInt32
    public let macOS: String
    public let nativeLimitOSAvailable: Bool
    public let nativePolicyValidated: Bool
    public let nativePolicyTrialBuild: Bool
    public let nativePolicyActivationAllowed: Bool
    public let nativePolicyInterfaceAvailable: Bool
    public let fullChargeOverride: FullChargeOverride
    public let capabilities: BatteryControlCapabilities?
    public let controlReadError: String?
    public let nativeState: NativeChargeState?
    public let nativeSupportedLimits: [Int]?
    public let nativeReadError: String?

    public static func read() -> Self {
        capture(model: BatteryMachine.model, os: ProcessInfo.processInfo.operatingSystemVersion,
                driver: SystemNativeChargeDriver(), hardware: RecoverableChargeHardware(),
                override: maccare_powerui_calibration_override(),
                policyAvailable: maccare_powerui_policy_is_available() == 1)
    }

    static func capture(model: String?, os: OperatingSystemVersion, driver: any NativeChargeDriver,
                        hardware: any ChargeHardware, override: Int32, policyAvailable: Bool) -> Self {
        var reading: NativeChargeReading?
        var readError: String?
        do { reading = try driver.read() } catch { readError = error.localizedDescription }
        var capabilities: BatteryControlCapabilities?
        var controlError: String?
        do { _ = try hardware.readSwitch(); capabilities = hardware.capabilities }
        catch { controlError = error.localizedDescription }
        return .init(model: model, effectiveUID: geteuid(), macOS: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                     nativeLimitOSAvailable: AppleSiliconChargeHardware.supportsNativeLimit(os),
                     nativePolicyValidated: AppleSiliconChargeHardware.nativePolicyValidated(model: model),
                     nativePolicyTrialBuild: AppleSiliconChargeHardware.m1MaxTrialBuild,
                     nativePolicyActivationAllowed: AppleSiliconChargeHardware.nativePolicyAllowed(model: model),
                     nativePolicyInterfaceAvailable: policyAvailable,
                     fullChargeOverride: .from(override),
                     capabilities: capabilities, controlReadError: controlError, nativeState: reading?.state,
                     nativeSupportedLimits: reading?.supportedLimits, nativeReadError: readError)
    }
}
