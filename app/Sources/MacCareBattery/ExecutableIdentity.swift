import Foundation

/// The file a running helper was started from. An app update replaces it under a helper kept
/// alive by a pending restoration, and clients then refuse to trust the process.
public struct ExecutableIdentity: Equatable, Sendable {
    private let device: UInt64
    private let inode: UInt64
    public init?(path: String) {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        device = UInt64(bitPattern: Int64(info.st_dev)); inode = info.st_ino
    }
}
