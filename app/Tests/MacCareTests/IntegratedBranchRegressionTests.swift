import Foundation
import Testing
@testable import MacCare

struct IntegratedBranchRegressionTests {
    @Test func diskCommandThatIgnoresTerminationStillReturnsAnUnavailableResult() {
        let start = ProcessInfo.processInfo.systemUptime
        #expect(throws: DiskHealthReader.ReadError.self) {
            // exec keeps the deliberately ignored SIGTERM without leaving a child process.
            _ = try DiskHealthReader.run("/bin/sh", ["-c", "trap '' TERM; exec /bin/sleep 2"], timeout: 0.05)
        }
        #expect(ProcessInfo.processInfo.systemUptime - start < 1.5)
    }

    @MainActor @Test func pngBeforeSizeMatchesTheFileActuallyProcessedAfterSelection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Changing.png")
        try Data([0]).write(to: source)
        let model = PNGOptimizationModel()
        model.select([source])
        #expect(model.items.first?.originalSize == 1)

        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("core/tests/fixtures/repetitive.png")
        let current = try Data(contentsOf: fixture)
        try current.write(to: source)
        await model.createCopies(in: directory)
        let item = try #require(model.items.first)
        let result = try #require(item.result)
        #expect(result.original_bytes == UInt64(current.count))
        #expect(item.originalSize == result.original_bytes,
                "The size presented beside the optimized result must describe the processed input.")
        #expect(try Data(contentsOf: source) == current)
    }
}
