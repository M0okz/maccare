import Foundation
import Combine

@MainActor
final class PNGOptimizationModel: ObservableObject {
    @Published private(set) var items: [PNGOptimizationItem] = []
    @Published private(set) var isRunning = false
    @Published private(set) var stopRequested = false
    @Published private(set) var completed = false
    @Published var message: String?
    private let optimize: @Sendable (String, String) throws -> PNGOptimizationResult

    init(optimize: @escaping @Sendable (String, String) throws -> PNGOptimizationResult = { try Engine.optimizePNGCopy(source: $0, destination: $1) }) {
        self.optimize = optimize
    }
    var copyCount: Int { items.filter { $0.result?.output_path != nil }.count }
    var savedBytes: UInt64 { items.reduce(0) { $0 + ($1.result?.savedBytes ?? 0) } }
    var processedCount: Int { items.filter { $0.result != nil || $0.error != nil }.count }
    var outputURLs: [URL] { items.compactMap { $0.result?.output_path }.map { URL(fileURLWithPath: $0) } }

    func select(_ urls: [URL]) {
        guard !isRunning else { return }
        guard urls.count <= 100 else { message = "Choisissez jusqu’à 100 images à la fois."; return }
        var seen = Set<URL>()
        items = urls.filter { seen.insert($0).inserted }.map { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { UInt64(max(0, $0)) } ?? 0
            return PNGOptimizationItem(url: url, originalSize: size)
        }
        completed = false; message = nil
    }
    func requestStop() { stopRequested = true }

    func createCopies(in directory: URL) async {
        guard !isRunning, !items.isEmpty else { return }
        isRunning = true; stopRequested = false; completed = false; message = nil
        for index in items.indices { items[index].result = nil; items[index].error = nil }
        let worker = optimize
        for index in items.indices {
            if stopRequested || Task.isCancelled { break }
            let source = items[index].url.path
            let destination = directory.path
            items[index].processing = true
            do {
                let result = try await Task.detached(priority: .utility) { try worker(source, destination) }.value
                items[index].result = result
            } catch {
                if case Engine.EngineError.engine(let message) = error { items[index].error = message }
                else { items[index].error = "Cette image n’a pas pu être traitée. L’original est conservé." }
            }
            items[index].processing = false
        }
        isRunning = false; completed = true
        if stopRequested || Task.isCancelled { message = "Opération arrêtée. Les copies terminées sont conservées." }
    }
}
