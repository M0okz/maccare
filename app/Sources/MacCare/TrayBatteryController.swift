import Combine
import Foundation

@MainActor
final class TrayBatteryController: ObservableObject {
    @Published private(set) var telemetry = TrayBatteryTelemetry()
    @Published private(set) var hasSampled = false
    private let sampler = TrayBatterySampler()
    private var accessoryHistory = TrayBatteryAccessoryHistory()

    func monitor() async {
        var first = true
        while !Task.isCancelled {
            let next = await sampler.read()
            guard !Task.isCancelled else { return }
            record(next)
            do { try await Task.sleep(for: first ? .seconds(1) : .seconds(5)) } catch { return }
            first = false
        }
    }

    func record(_ next: TrayBatteryTelemetry, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        var stable = next
        stable.accessories = accessoryHistory.record(next.accessories, at: time)
        telemetry = stable
        hasSampled = true
    }
}
