// Read-only integration check, signed with the same development identity as MacCare.
// Build with HelperProtocol.swift; never shipped inside the application.
import Foundation

let connection = NSXPCConnection(machServiceName: HelperIdentity.machService, options: .privileged)
connection.remoteObjectInterface = NSXPCInterface(with: MacCareHelperXPC.self)
connection.setCodeSigningRequirement(HelperIdentity.helperRequirement)
connection.resume()
let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    fputs("XPC: \(error.localizedDescription)\n", stderr)
    exit(2)
}
guard let helper = proxy as? MacCareHelperXPC else { exit(3) }
helper.version { version, _ in
    guard version == HelperIdentity.protocolVersion else {
        fputs("Unexpected helper protocol: \(version)\n", stderr); exit(4)
    }
    helper.battery(command: "status", sessionID: "", configurationJSON: "{}") { json in
        print(json)
        connection.invalidate()
        exit(0)
    }
}
DispatchQueue.global().asyncAfter(deadline: .now() + 10) { fputs("XPC timeout\n", stderr); exit(5) }
RunLoop.main.run()
