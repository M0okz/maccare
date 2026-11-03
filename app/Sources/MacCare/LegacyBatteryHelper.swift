import Foundation
import MacCareHelperProtocol

@objc private protocol LegacyBatteryXPC {
    func battery(command: String, configurationJSON: String, withReply reply: @escaping (String) -> Void)
}

enum LegacyBatteryHelper {
    /// Only called by explicit helper deactivation. Never activates/reconfigures old hardware.
    static func restoreBeforeUnregister() async throws {
        let stopped = try await call("disable")
        guard stopped["active"] as? Bool == false,
              stopped["error"] == nil || stopped["error"] is NSNull else {
            throw HelperClient.HelperError.unavailable("l’ancien assistant n’a pas confirmé le retour à la charge normale")
        }
    }
    private static func call(_ command: String) async throws -> [String: Any] {
        let connection = NSXPCConnection(machServiceName: HelperIdentity.machService, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: LegacyBatteryXPC.self)
        connection.setCodeSigningRequirement(HelperIdentity.helperRequirement)
        connection.resume()
        defer { connection.invalidate() }
        let json: String = try await withCheckedThrowingContinuation { continuation in
            let reply = LegacyReply(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
                reply.finish(.failure(HelperClient.HelperError.unavailable("ancien assistant : délai dépassé")))
            }
            let object = connection.remoteObjectProxyWithErrorHandler { error in reply.finish(.failure(error)) }
            guard let helper = object as? LegacyBatteryXPC else {
                reply.finish(.failure(HelperClient.HelperError.unavailable("ancienne interface indisponible"))); return
            }
            helper.battery(command: command, configurationJSON: "{}") { reply.finish(.success($0)) }
        }
        guard let result = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              result["active"] is Bool else {
            throw HelperClient.HelperError.unavailable("ancien état de batterie invalide")
        }
        return result
    }
}

/// Lock protects both taking and resuming the continuation, including the timeout/error race.
private final class LegacyReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    init(_ continuation: CheckedContinuation<String, Error>) { self.continuation = continuation }
    func finish(_ result: Result<String, Error>) {
        lock.lock()
        let pending = continuation; continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
