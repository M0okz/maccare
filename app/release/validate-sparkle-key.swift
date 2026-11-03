import CryptoKit
import Foundation

let input = FileHandle.standardInput.readDataToEndOfFile()
guard CommandLine.arguments.count == 2,
      let encoded = String(data: input, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
      let seed = Data(base64Encoded: encoded), seed.count == 32,
      let expected = Data(base64Encoded: CommandLine.arguments[1]), expected.count == 32,
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed),
      key.publicKey.rawRepresentation == expected else {
    FileHandle.standardError.write(Data("Les clés Sparkle publique et privée ne correspondent pas (graine Ed25519 de 32 octets requise).\n".utf8))
    exit(1)
}
