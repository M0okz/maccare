import Foundation
import CMacCareSMC
import MacCareHelperProtocol

private struct SystemFans: FanBoostHardware {
    static let marker = Audit.directory.appendingPathComponent("fan-recovery.bits")

    func automaticModes() throws -> [Bool] {
        var state = MCFanSnapshot()
        guard maccare_fans_read(&state) == 0, (1...8).contains(state.count) else { throw FanControlError.unsupported }
        let supported = withUnsafeBytes(of: state.controllable) { Array($0.prefix(Int(state.count))) }
        guard supported.allSatisfy({ $0 == 1 }) else { throw FanControlError.unsupported }
        return withUnsafeBytes(of: state.mode) { $0.prefix(Int(state.count)).map { $0 == 0 } }
    }

    func thermalsAllowBoost() -> Bool {
        let state = ProcessInfo.processInfo.thermalState
        var temperature: Double = 0
        return (state == .nominal || state == .fair) && maccare_cpu_temperature(&temperature) == 0 && temperature < 85
    }

    func fansResponding(mask: UInt8) -> Bool {
        var state = MCFanSnapshot()
        guard maccare_fans_read(&state) == 0, (1...8).contains(state.count) else { return false }
        let speeds = withUnsafeBytes(of: state.current) { Array($0.bindMemory(to: Double.self)) }
        let valid = withUnsafeBytes(of: state.currentValid) { Array($0) }
        let modes = withUnsafeBytes(of: state.mode) { Array($0) }
        return (0..<8).allSatisfy { index in
            mask & (1 << index) == 0 || (index < Int(state.count) && modes[index] == 1 && valid[index] == 1 && speeds[index] > 0)
        }
    }

    func boost(fan: Int, maximum: Bool, replacingBoost: Bool) -> (success: Bool, attempted: Bool) {
        var attempted: UInt8 = 0
        let result = maccare_fan_boost(UInt32(fan), maximum ? 1 : 0, replacingBoost ? 1 : 0, &attempted)
        return (result == 0, attempted != 0)
    }

    func restore(fan: Int) -> Bool { maccare_fan_auto(UInt32(fan)) == 0 }

    func record(mask: UInt8) throws {
        let files = FileManager.default
        if mask == 0 {
            try files.removeItem(at: Self.marker)
        } else {
            try files.createDirectory(at: Audit.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try Data([mask]).write(to: Self.marker, options: .atomic)
        }
    }
}

enum FanService {
    private static let queue = DispatchQueue(label: "org.maccare.helper.fans")
    private static var session: FanBoostSession?
    private static var watchdog: DispatchSourceTimer?

    static func start() {
        queue.sync {
            do {
                let mask: UInt8
                do {
                    let data = try Data(contentsOf: SystemFans.marker)
                    guard data.count == 1, let bits = data.first else { throw FanControlError.restore }
                    mask = bits
                } catch CocoaError.fileReadNoSuchFile { mask = 0 }
                let recovered = FanBoostSession(hardware: SystemFans(), recoveryMask: mask)
                session = recovered
                defer { updateWatchdog() }
                try recovered.apply(.automatic, now: .now)
            } catch {
                NSLog("MacCareHelper fan recovery: %@", error.localizedDescription)
            }
        }
    }

    static func execute(_ raw: String, uid: uid_t, reply: @escaping (String) -> Void) {
        Idle.begin()
        queue.async {
            defer { Idle.end() }
            guard uid >= 501, let preset = FanPreset(rawValue: raw), let session else {
                reply("Commande de ventilation indisponible.")
                return
            }
            do {
                try session.apply(preset, now: .now)
                updateWatchdog()
                reply("")
            } catch {
                updateWatchdog()
                reply(error.localizedDescription)
            }
        }
    }

    private static func updateWatchdog() {
        guard session?.mask != 0 else {
            if let watchdog { watchdog.cancel(); self.watchdog = nil; Idle.end() }
            return
        }
        guard watchdog == nil else { return }
        Idle.begin()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler {
            try? session?.check(now: .now)
            updateWatchdog()
        }
        watchdog = timer
        timer.resume()
    }
}
