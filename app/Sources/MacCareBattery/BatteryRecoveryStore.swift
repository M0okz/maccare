import Foundation
import Darwin

/// Fixed root-owned store in production. Test fixtures use a private temporary directory.
/// Refuse links, wrong ownership, broad permissions, corrupt/oversized records and unknown versions.
public struct BatteryRecoveryStore {
    public let directory: URL
    private let owner: uid_t
    private let name = "battery-charge-recovery"
    public init(directory: URL, owner: uid_t = 0) { self.directory = directory; self.owner = owner }
    private func openDirectory(create: Bool) throws -> Int32 {
        if create {
            if mkdir(directory.path, 0o700) != 0 && errno != EEXIST { throw issue() }
        }
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw issue() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == owner, info.st_mode & 0o077 == 0 else {
            close(fd); throw StoreError()
        }
        return fd
    }
    public func load() throws -> BatteryRecoveryRecord? {
        if !FileManager.default.fileExists(atPath: directory.path) {
            // fileExists follows symlinks; a dangling link must still fail closed.
            var info = stat()
            if lstat(directory.path, &info) != 0 && errno == ENOENT { return nil }
        }
        let dir = try openDirectory(create: false)
        defer { close(dir) }
        let fd = openat(dir, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0 && errno == ENOENT { return nil }
        guard fd >= 0 else { throw issue() }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == owner,
              info.st_mode & 0o077 == 0, info.st_nlink == 1, info.st_size > 0, info.st_size <= 1024 else { throw StoreError() }
        var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
        let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        guard count == bytes.count,
              let record = try? JSONDecoder().decode(BatteryRecoveryRecord.self, from: Data(bytes)), record.isValid else { throw StoreError() }
        return record
    }
    public func save(_ record: BatteryRecoveryRecord) throws {
        guard record.isValid else { throw StoreError() }
        let dir = try openDirectory(create: true)
        defer { close(dir) }
        // Never truncate a pending restoration, even if the record looks identical.
        let fd = openat(dir, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw issue() }
        defer { close(fd) }
        let data = try JSONEncoder().encode(record)
        let count = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard count == data.count, fsync(fd) == 0, fsync(dir) == 0 else { throw issue() }
    }
    public func clear() throws {
        let dir = try openDirectory(create: false)
        defer { close(dir) }
        guard unlinkat(dir, name, 0) == 0 || errno == ENOENT else { throw issue() }
        guard fsync(dir) == 0 else { throw issue() }
    }
    private func issue() -> Error { StoreError() }
    private struct StoreError: LocalizedError {
        var errorDescription: String? { "Le journal de restauration de la batterie est absent, invalide ou insuffisamment protégé. Le contrôle matériel est bloqué." }
    }
}
