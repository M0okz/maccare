import Foundation
import Combine

@MainActor
final class DiskHealthModel: ObservableObject {
    @Published private(set) var report: DiskHealthReport?
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    @Published private(set) var measuredAt: Date?
    private var generation = UUID()
    private let read: @Sendable (String) throws -> DiskHealthReport

    init(read: @escaping @Sendable (String) throws -> DiskHealthReport = { try DiskHealthReader.read(volumePath: $0) }) { self.read = read }

    func refresh(at path: String) async {
        let token = UUID(); generation = token
        isLoading = true; report = nil; message = nil; measuredAt = nil
        defer { if generation == token { isLoading = false } }
        let reader = read
        do {
            let result = try await Task.detached(priority: .utility) { try reader(path) }.value
            guard generation == token, !Task.isCancelled else { return }
            report = result; measuredAt = Date()
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            message = DiskHealthReader.ReadError.unavailable.localizedDescription
        }
    }
}
