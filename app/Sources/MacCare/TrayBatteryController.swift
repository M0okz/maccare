import Combine
import Foundation

@MainActor
final class TrayBatteryController: ObservableObject {
    @Published private(set) var telemetry = TrayBatteryTelemetry()
    @Published private(set) var hasSampled = false
    private let sampler = TrayBatterySampler()

    func monitor() async {
        var first = true
        while !Task.isCancelled {
            let next = await sampler.read()
            guard !Task.isCancelled else { return }
            telemetry = next
            hasSampled = true
            do { try await Task.sleep(for: first ? .seconds(1) : .seconds(5)) } catch { return }
            first = false
        }
    }
}
