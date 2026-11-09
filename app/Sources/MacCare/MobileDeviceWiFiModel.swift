import Foundation
import Combine

@MainActor
final class MobileDeviceWiFiModel: ObservableObject {
    struct Device: Decodable, Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let wifiEnabled: Bool?
        let usbConnected: Bool
        let canConfigure: Bool

        var valid: Bool {
            id.count == 64 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } &&
                !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 128 &&
                (!canConfigure || (usbConnected && wifiEnabled != nil))
        }
    }
    typealias Execute = @Sendable ([String]) async -> MobileDeviceBatteryReader.Output
    @Published private(set) var devices: [Device] = []
    @Published private(set) var busy = false
    @Published private(set) var loaded = false
    @Published private(set) var message: String?
    @Published private(set) var isError = false
    private let execute: Execute

    init(execute: @escaping Execute = { await MobileDeviceBatteryReader.execute(arguments: $0) }) { self.execute = execute }

    nonisolated static func parse(_ data: Data) -> [Device] {
        guard data.count <= 32_768, let text = String(data: data, encoding: .utf8) else { return [] }
        var devices: [Device] = []
        for line in text.split(separator: "\n").prefix(24) {
            guard let device = try? JSONDecoder().decode(Device.self, from: Data(line.utf8)), device.valid else { continue }
            if let index = devices.firstIndex(where: { $0.id == device.id }) {
                if device.usbConnected { devices[index] = device }
            } else { devices.append(device) }
        }
        return devices
    }

    func refresh() async {
        guard !busy, !Task.isCancelled else { return }
        busy = true; message = nil; isError = false
        defer { busy = false; loaded = true }
        let output = await execute(["--list-wifi"])
        guard !Task.isCancelled else { return }
        let complete = output.exitedNormally && MobileDeviceBatteryReader.parse(output.data).complete
        if complete { devices = Self.parse(output.data) }
        else { isError = true; message = "Lecture impossible. Déverrouillez l’appareil, branchez-le en USB, puis réessayez." }
    }

    func setWiFi(for device: Device, enabled: Bool) async {
        guard !busy, device.valid, device.canConfigure, devices.contains(device), !Task.isCancelled else { return }
        busy = true; message = nil; isError = false
        defer { busy = false }
        let output = await execute(["--set-wifi", device.id, enabled ? "on" : "off"])
        // An explicit change may complete even if its view closed. Report the verified state when reopened.
        let updated = Self.parse(output.data)
        if let current = updated.first(where: { $0.id == device.id }), let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = current
        }
        if output.exitedNormally, MobileDeviceBatteryReader.parse(output.data).complete,
           updated.contains(where: { $0.id == device.id && $0.wifiEnabled == enabled }) {
            message = enabled ? "Accès Wi-Fi activé pour \(device.name). Gardez l’appareil et le Mac sur le même réseau après avoir débranché le câble."
                : "Accès Wi-Fi désactivé pour \(device.name). Le suivi reste disponible en USB."
        } else {
            isError = true
            message = "Le changement n’a pas pu être confirmé. Déverrouillez l’appareil, branchez-le en USB, puis réessayez."
        }
    }
}
