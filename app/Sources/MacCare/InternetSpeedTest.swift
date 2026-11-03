import Foundation

struct InternetSpeedResult: Sendable {
    let downloadMbps: Double
    let uploadMbps: Double
    let latencyMilliseconds: Double
    let transferredBytes: Int
    let completedAt: Date
}

enum InternetSpeedEvent: Sendable {
    case phase(String)
    case latency(Double)
    case download(Double)
    case upload(Double)
}

struct SpeedTransfer: Sendable {
    let bytes: Int
    let seconds: Double
    var megabitsPerSecond: Double { Double(bytes) * 8 / seconds / 1_000_000 }
}

protocol SpeedTestTransport: Sendable {
    func download(bytes: Int) async throws -> SpeedTransfer
    func upload(bytes: Int) async throws -> SpeedTransfer
}

enum InternetSpeedError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case incompleteTransfer
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Le serveur de mesure n’a pas renvoyé une réponse valide."
        case .httpStatus(let code): return "Le serveur de mesure a refusé la requête (HTTP \(code)). Réessayez dans quelques instants."
        case .incompleteTransfer: return "Le transfert de mesure est incomplet. Réessayez lorsque la connexion est stable."
        }
    }
}

/// Requêtes HTTP natives vers les points de mesure publics de Cloudflare.
/// Session sans cookies/cache ; seuls des octets synthétiques sont envoyés.
actor CloudflareSpeedTransport: SpeedTestTransport {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        config.httpMaximumConnectionsPerHost = 1
        session = URLSession(configuration: config)
    }

    deinit { session.invalidateAndCancel() }

    private func request(path: String, bytes: Int? = nil) -> URLRequest {
        var url = URLComponents(string: "https://speed.cloudflare.com/\(path)")!
        var items = [URLQueryItem(name: "maccare", value: UUID().uuidString)]
        if let bytes { items.append(URLQueryItem(name: "bytes", value: String(bytes))) }
        url.queryItems = items
        var request = URLRequest(url: url.url!)
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return request
    }

    func download(bytes: Int) async throws -> SpeedTransfer {
        try Task.checkCancellation()
        let started = ProcessInfo.processInfo.systemUptime
        let (file, response) = try await session.download(for: request(path: "__down", bytes: bytes))
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw InternetSpeedError.invalidResponse }
        guard http.statusCode == 200 else { throw InternetSpeedError.httpStatus(http.statusCode) }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let count = (attributes[.size] as? NSNumber)?.intValue ?? -1
        guard count == bytes else { throw InternetSpeedError.incompleteTransfer }
        return .init(bytes: count, seconds: max(ProcessInfo.processInfo.systemUptime - started, 0.000_001))
    }

    func upload(bytes: Int) async throws -> SpeedTransfer {
        try Task.checkCancellation()
        // Même contrat que le moteur public Cloudflare : texte synthétique et taille déclarée.
        let payload = Data(repeating: 0x30, count: bytes)
        var request = request(path: "__up", bytes: bytes)
        request.httpMethod = "POST"
        request.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(String(bytes), forHTTPHeaderField: "Content-Length")
        let started = ProcessInfo.processInfo.systemUptime
        let (_, response) = try await session.upload(for: request, from: payload)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw InternetSpeedError.invalidResponse }
        guard http.statusCode == 200 else { throw InternetSpeedError.httpStatus(http.statusCode) }
        return .init(bytes: bytes, seconds: max(ProcessInfo.processInfo.systemUptime - started, 0.000_001))
    }
}

/// Test HTTP court à un flux, borné à 72 Mo de données utiles.
/// La durée inclut la latence HTTP : mesure effective vers ce serveur, pas capacité garantie.
struct InternetSpeedRunner: Sendable {
    let transport: any SpeedTestTransport

    func run(update: @Sendable (InternetSpeedEvent) async -> Void) async throws -> InternetSpeedResult {
        await update(.phase("Mesure de la latence…"))
        // Premier échange hors calcul : établissement de la connexion TLS.
        _ = try await transport.download(bytes: 0)
        var latencies: [Double] = []
        for _ in 0..<5 {
            try Task.checkCancellation()
            let transfer = try await transport.download(bytes: 0)
            latencies.append(transfer.seconds * 1_000)
        }
        let latency = latencies.sorted()[latencies.count / 2]
        await update(.latency(latency))
        var total = 0
        await update(.phase("Test du téléchargement…"))
        let download = try await measure(sizes: [1_000_000, 10_000_000, 25_000_000], total: &total) { value in
            await update(.download(value))
        }
        await update(.phase("Test de l’envoi…"))
        let upload = try await measure(sizes: [1_000_000, 10_000_000, 25_000_000], upload: true, total: &total) { value in
            await update(.upload(value))
        }
        try Task.checkCancellation()
        return .init(downloadMbps: download, uploadMbps: upload, latencyMilliseconds: latency,
                     transferredBytes: total, completedAt: Date())
    }

    private func measure(sizes: [Int], upload: Bool = false, total: inout Int,
                         update: @Sendable (Double) async -> Void) async throws -> Double {
        var last: Double = 0
        for bytes in sizes {
            try Task.checkCancellation()
            let transfer = try await (upload ? transport.upload(bytes: bytes) : transport.download(bytes: bytes))
            guard transfer.bytes == bytes, transfer.seconds.isFinite, transfer.seconds > 0 else {
                throw InternetSpeedError.incompleteTransfer
            }
            total += transfer.bytes
            last = transfer.megabitsPerSecond
            await update(last)
            // Les petits transferts ne suffisent pas sur une liaison rapide.
            if transfer.seconds >= 2 { break }
        }
        return last
    }
}

@MainActor
final class InternetSpeedTest: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var phase = "Prêt à mesurer"
    @Published private(set) var downloadMbps: Double?
    @Published private(set) var uploadMbps: Double?
    @Published private(set) var latencyMilliseconds: Double?
    @Published private(set) var result: InternetSpeedResult?
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    private var runID: UUID?

    func start(transport: any SpeedTestTransport = CloudflareSpeedTransport()) {
        guard !running else { return }
        let id = UUID()
        runID = id
        running = true
        error = nil
        result = nil
        downloadMbps = nil; uploadMbps = nil; latencyMilliseconds = nil
        task = Task { [weak self] in
            do {
                let result = try await InternetSpeedRunner(transport: transport).run { [weak self] event in
                    await self?.receive(event, id: id)
                }
                guard let self, self.runID == id, !Task.isCancelled else { return }
                self.result = result
                self.phase = "Test terminé"
                self.running = false
                self.task = nil
            } catch {
                guard let self, self.runID == id else { return }
                self.running = false
                self.error = Task.isCancelled ? nil : "\(self.phase) \(error.localizedDescription)"
                self.phase = Task.isCancelled ? "Test arrêté" : "Test impossible"
                self.task = nil
            }
        }
    }

    func cancel() {
        guard running else { return }
        runID = nil
        task?.cancel()
        task = nil
        running = false
        result = nil
        downloadMbps = nil; uploadMbps = nil; latencyMilliseconds = nil
        phase = "Test arrêté"
    }

    private func receive(_ event: InternetSpeedEvent, id: UUID) {
        guard runID == id else { return }
        switch event {
        case .phase(let title): phase = title
        case .latency(let value): latencyMilliseconds = value
        case .download(let value): downloadMbps = value
        case .upload(let value): uploadMbps = value
        }
    }
}
