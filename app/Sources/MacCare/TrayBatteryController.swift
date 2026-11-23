import Combine
import Foundation

@MainActor
final class TrayBatteryController: ObservableObject {
    @Published private(set) var telemetry = TrayBatteryTelemetry()
    @Published private(set) var hasSampled = false
    private let sampler = TrayBatterySampler()
    private let accessoryHistory: TrayBatteryAccessoryHistory
    private(set) var homeAccessories: [TrayBatteryTelemetry.Accessory]

    init(accessoryHistory: TrayBatteryAccessoryHistory? = nil) {
        let history = accessoryHistory ?? TrayBatteryAccessoryHistory()
        self.accessoryHistory = history
        homeAccessories = history.rings.map {
            var accessory = $0
            accessory.isLastKnown = true
            return accessory
        }
    }

    func monitor(includeAccessories: () -> Bool = { true },
                 onProcesses: (([TrayProcess]) -> Void)? = nil) async {
        var first = true
        while !Task.isCancelled {
            let next = await sampler.read(includeAccessories: includeAccessories(), includeProcessList: onProcesses != nil)
            guard !Task.isCancelled else { return }
            record(next.telemetry)
            if let processes = next.processes { onProcesses?(processes) }
            do { try await Task.sleep(for: first ? .seconds(1) : .seconds(5)) } catch { return }
            first = false
        }
    }

    func record(_ next: TrayBatteryTelemetry, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        var stable = next
        stable.accessories = accessoryHistory.record(next.accessories, at: time)
        homeAccessories = accessoryHistory.rings
        telemetry = stable
        hasSampled = true
    }
}
