import Foundation
import Testing
import MacCareBattery

struct ExecutableIdentityTests {
    private func temporaryFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("a".utf8).write(to: url)
        return url
    }
    @Test func sameFileKeepsItsIdentityEvenWhenRewrittenInPlace() throws {
        let url = try temporaryFile(); defer { try? FileManager.default.removeItem(at: url) }
        let started = try #require(ExecutableIdentity(path: url.path))
        let handle = try FileHandle(forWritingTo: url); try handle.write(contentsOf: Data("b".utf8)); try handle.close()
        #expect(ExecutableIdentity(path: url.path) == started)
    }
    @Test func replacingTheFileChangesItsIdentity() throws {
        let url = try temporaryFile(), other = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let started = try #require(ExecutableIdentity(path: url.path))
        _ = try FileManager.default.replaceItemAt(url, withItemAt: other)
        #expect(ExecutableIdentity(path: url.path) != started)
    }
    @Test func removingTheFileIsDetected() throws {
        let url = try temporaryFile()
        let started = try #require(ExecutableIdentity(path: url.path))
        try FileManager.default.removeItem(at: url)
        #expect(ExecutableIdentity(path: url.path) != started)
    }
}
