import Foundation
import Darwin

/// One bounded subprocess; default battery reads never change device settings.
enum MobileDeviceBatteryReader {
    struct Record: Decodable, Sendable {
        enum Kind: String, Decodable, Sendable { case iphone, ipad, watch }
        let id: String
        let name: String
        let kind: Kind
        let percent: Int
        let viaPhone: Bool

        var accessory: TrayBatteryTelemetry.Accessory? {
            guard id.count == 64, id.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 128,
                  (0...100).contains(percent), viaPhone == (kind == .watch) else { return nil }
            let symbol = kind == .watch ? "applewatch" : kind.rawValue
            return .init(id: "mobile:\(id)", name: name, symbol: symbol, percent: percent, viaPhone: viaPhone)
        }
    }
    struct Result: Sendable {
        var accessories: [TrayBatteryTelemetry.Accessory] = []
        var complete = false
    }
    struct Output: Sendable {
        var data = Data()
        var exitedNormally = false
    }

    static func parse(_ data: Data) -> Result {
        guard data.count <= 32_768, let text = String(data: data, encoding: .utf8) else { return Result() }
        struct Status: Decodable { let status: String }
        var result = Result()
        var identifiers: Set<String> = []
        for line in text.split(separator: "\n").prefix(24) {
            let data = Data(line.utf8)
            if let status = try? JSONDecoder().decode(Status.self, from: data) {
                result.complete = status.status == "complete"
            } else if let record = try? JSONDecoder().decode(Record.self, from: data),
                      let accessory = record.accessory, identifiers.insert(accessory.id).inserted {
                result.accessories.append(accessory)
            }
        }
        return result
    }

    static func read(executable: URL? = Bundle.main.executableURL?.deletingLastPathComponent()
                     .appendingPathComponent("MacCareDeviceBatteryProbe")) async -> Result {
        let output = await execute(arguments: [], executable: executable)
        var result = parse(output.data)
        result.complete = result.complete && output.exitedNormally
        return result
    }

    static func execute(arguments: [String], executable: URL? = Bundle.main.executableURL?.deletingLastPathComponent()
                        .appendingPathComponent("MacCareDeviceBatteryProbe")) async -> Output {
        guard !Task.isCancelled, let executable,
              FileManager.default.isExecutableFile(atPath: executable.path) else { return Output() }
        // Foundation's synchronous process API runs outside the cooperative executor.
        // A read already in flight finishes within seven seconds; cancellation starts no further read.
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: run(executable: executable, arguments: arguments))
            }
        }
    }

    private static func run(executable: URL, arguments: [String]) -> Output {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return Output() }
        // The child also has an alarm; this second deadline covers startup and unexpected hangs.
        let deadline = DispatchWorkItem {
            if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 7, execute: deadline)
        defer { deadline.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard data.count <= 32_768 else { return Output() }
        return .init(data: data, exitedNormally: process.terminationReason == .exit && process.terminationStatus == 0)
    }
}
