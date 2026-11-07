import Foundation
import ImageIO
import Testing
@testable import MacCare

struct NativePNGOptimizationTests {
    private var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("core/tests/fixtures/repetitive.png")
    }

    @Test func nativeEngineCreatesSmallerCopyWithIdenticalDecodedPixelsAndKeepsOriginal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Capture.png")
        try FileManager.default.copyItem(at: fixture, to: source)
        let before = try Data(contentsOf: source)
        let result = try Engine.optimizePNGCopy(source: source.path, destination: directory.path)
        let copy = try #require(result.output_path)
        #expect(copy != source.path)
        #expect(result.optimized_bytes < result.original_bytes)
        #expect(try Data(contentsOf: source) == before)
        let originalSource = try #require(CGImageSourceCreateWithURL(source as CFURL, nil))
        let copySource = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: copy) as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(originalSource, 0, nil))
        let optimized = try #require(CGImageSourceCreateImageAtIndex(copySource, 0, nil))
        #expect(image.width == optimized.width)
        #expect(image.height == optimized.height)
        #expect(image.bitsPerComponent == optimized.bitsPerComponent)
        #expect(image.alphaInfo == optimized.alphaInfo)
        let pixels = try #require(image.dataProvider?.data) as Data
        let optimizedPixels = try #require(optimized.dataProvider?.data) as Data
        #expect(pixels == optimizedPixels)
        #expect(try Data(contentsOf: URL(fileURLWithPath: copy)).range(of: Data("MacCare fixture".utf8)) != nil)
    }

    @MainActor @Test func nativeFilesModelReportsCopiesRatherThanFreedDiskSpace() async {
        let model = PNGOptimizationModel { _, _ in
            PNGOptimizationResult(original_bytes: 1000, optimized_bytes: 500, output_path: "/fixture/copy.png")
        }
        model.select([URL(fileURLWithPath: "/fixture/input.png")])
        await model.createCopies(in: URL(fileURLWithPath: "/fixture"))
        #expect(model.copyCount == 1)
        #expect(model.savedBytes == 500)
        #expect(model.completed)
        #expect(model.isRunning == false)
    }

    @MainActor @Test func cancelledBatchDoesNotStartAnyImage() async {
        let model = PNGOptimizationModel { _, _ in
            Issue.record("A cancelled batch must not start optimization")
            return PNGOptimizationResult(original_bytes: 1, optimized_bytes: 1, output_path: nil)
        }
        model.select([URL(fileURLWithPath: "/fixture/input.png")])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.createCopies(in: URL(fileURLWithPath: "/fixture"))
        }
        await task.value
        #expect(model.processedCount == 0)
        #expect(model.copyCount == 0)
        #expect(model.isRunning == false)
    }
}
