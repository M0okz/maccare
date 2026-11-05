import MacCareBattery

struct BatteryAlertObservation {
    let expected: Bool
    let helperReady: Bool
    let status: BatteryProtectionStatus?
    let cancellation: Int
    let terminating: Bool
    var limitConfirmed: Bool {
        guard status?.capabilities?.backend == .nativePolicy else { return true }
        return status?.chargeApplication?.registered == true
    }
    var healthy: Bool {
        guard helperReady, let status, status.active, status.error == nil, !status.restoring else { return false }
        if status.capabilities?.backend == .nativePolicy, !limitConfirmed {
            guard let application = status.chargeApplication else { return false }
            return !status.snapshot.onAC || application.elapsed < NativeChargePolicyHardware.registrationGrace
        }
        return true
    }
}
