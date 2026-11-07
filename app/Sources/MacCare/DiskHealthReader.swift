import Foundation

/// Fixed read-only commands, no sudo, no self-tests, no SMART setting changes.
enum DiskHealthReader {
    enum ReadError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Ces informations ne sont pas accessibles pour ce disque. Certains supports externes ne les transmettent pas à macOS." }
    }

    static func physicalDevice(info: [String: Any], lookup: (String) throws -> [String: Any]) throws -> String {
        var physical = info
        if let stores = info["APFSPhysicalStores"] as? [[String: Any]] {
            guard stores.count == 1, let device = stores.first?["APFSPhysicalStore"] as? String, validDevice(device) else { throw ReadError.unavailable }
            physical = try lookup("/dev/" + device)
        }
        guard physical["VirtualOrPhysical"] as? String != "Virtual",
              physical["BusProtocol"] as? String != "Disk Image" else { throw ReadError.unavailable }
        let whole = physical["ParentWholeDisk"] as? String ?? physical["DeviceIdentifier"] as? String
        guard let whole, whole.range(of: "^disk[0-9]+$", options: .regularExpression) != nil else { throw ReadError.unavailable }
        return "/dev/" + whole
    }
    private static func validDevice(_ value: String) -> Bool {
        value.range(of: "^disk[0-9]+(?:s[0-9]+)*$", options: .regularExpression) != nil
    }

    static func read(volumePath: String, bundleURL: URL = Bundle.main.bundleURL) throws -> DiskHealthReport {
        let tool = bundleURL.appendingPathComponent("Contents/Helpers/smartctl")
        let database = bundleURL.appendingPathComponent("Contents/Resources/smartmontools/drivedb.h")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { throw ReadError.unavailable }
        func info(_ path: String) throws -> [String: Any] {
            let output = try run("/usr/sbin/diskutil", ["info", "-plist", path])
            guard output.status == 0, let value = try PropertyListSerialization.propertyList(from: output.data, format: nil) as? [String: Any] else { throw ReadError.unavailable }
            return value
        }
        let volume = try URL(fileURLWithPath: volumePath).resourceValues(forKeys: [.volumeURLKey]).volume
        guard let volume else { throw ReadError.unavailable }
        let device = try physicalDevice(info: info(volume.path), lookup: info)
        let output = try run(tool.path, ["-j", "-H", "-A", "-i", "-q", "noserial", "-B", database.path, device])
        return try parse(output.data, exitStatus: output.status)
    }

    static func parse(_ data: Data, exitStatus: Int32) throws -> DiskHealthReport {
        // smartctl is a bitmask: health warnings are valid reports, not invocation errors.
        guard exitStatus >= 0, exitStatus & 7 == 0,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ReadError.unavailable }
        let status = object["smart_status"] as? [String: Any]
        let passed = status?["passed"] as? Bool
        let nvme = object["nvme_smart_health_information_log"] as? [String: Any] ?? [:]
        let temperature = (object["temperature"] as? [String: Any])?["current"] as? Int
        let endurance = nvme["percentage_used"] as? Int ?? (object["endurance_used"] as? [String: Any])?["current"] as? Int
        let spare = nvme["available_spare"] as? Int
        let hours = nvme["power_on_hours"] as? UInt64 ?? (object["power_on_time"] as? [String: Any])?["hours"] as? UInt64
        let cycles = nvme["power_cycles"] as? UInt64 ?? object["power_cycle_count"] as? UInt64
        let mediaErrors = nvme["media_errors"] as? UInt64
        let units = nvme["data_units_written"] as? UInt64
        let written = units?.multipliedReportingOverflow(by: 512_000)
        let bytes = written?.overflow == false ? written?.partialValue : nil
        guard passed != nil || temperature != nil || endurance != nil else { throw ReadError.unavailable }
        return DiskHealthReport(model: object["model_name"] as? String, passed: passed,
                                warning: exitStatus & 0xF8 != 0 || passed == false || (nvme["critical_warning"] as? Int ?? 0) != 0 || (mediaErrors ?? 0) > 0 || (endurance ?? 0) >= 100,
                                temperature: temperature.flatMap { (-40...150).contains($0) ? $0 : nil },
                                enduranceUsed: endurance.flatMap { $0 >= 0 ? $0 : nil }, spareAvailable: spare.flatMap { (0...100).contains($0) ? $0 : nil },
                                hours: hours, powerCycles: cycles, writtenBytes: bytes, mediaErrors: mediaErrors)
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, data: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 12, execute: deadline)
        defer { deadline.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, data.count <= 1_048_576 else { throw ReadError.unavailable }
        return (process.terminationStatus, data)
    }
}
