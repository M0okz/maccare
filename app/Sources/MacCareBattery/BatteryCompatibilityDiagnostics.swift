import Foundation
import CMacCarePowerUI
import Darwin

/// Read-only compatibility evidence. Contains a model identifier, never a serial
/// number, recovery identity, preference write, or probe by activation.
public struct BatteryCompatibilityDiagnostics: Codable, Sendable {
    public enum FullChargeOverride: String, Codable, Sendable { case inactive, active, unknown }
    public let model: String?
    public let effectiveUID: UInt32
    public let macOS: String
    public let nativeLimitOSAvailable: Bool
    public let nativePolicyValidated: Bool
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
                     nativePolicyInterfaceAvailable: policyAvailable,
                     fullChargeOverride: override < 0 ? .unknown : (override == 0 ? .inactive : .active),
                     capabilities: capabilities, controlReadError: controlError, nativeState: reading?.state,
                     nativeSupportedLimits: reading?.supportedLimits, nativeReadError: readError)
    }
}
