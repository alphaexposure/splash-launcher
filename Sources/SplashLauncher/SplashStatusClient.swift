import Foundation

/// Runtime values reported by Splash, separate from the launcher's requested settings.
struct SplashStatus: Decodable, Equatable {
    struct Instance: Decodable, Equatable {
        let model: String?
        let host: String?
        let port: Int?
    }

    struct HTTP: Decodable, Equatable {
        let maxRequestBytes: Int?
        enum CodingKeys: String, CodingKey { case maxRequestBytes = "max_request_bytes" }
    }

    struct MemoryActual: Decodable, Equatable {
        let currentBytes: Int?
        enum CodingKeys: String, CodingKey { case currentBytes = "current_bytes" }
    }

    struct MemoryGovernor: Decodable, Equatable {
        let limitBytes: Int?
        enum CodingKeys: String, CodingKey { case limitBytes = "limit_bytes" }
    }

    struct Metrics: Decodable, Equatable {
        let prefillInputTokens: Int?
        let decodeOutputTokens: Int?
        let prefillTokensPerSecond: Double?
        let decodeTokensPerSecond: Double?

        enum CodingKeys: String, CodingKey {
            case prefillInputTokens = "prefill_input_tokens"
            case decodeOutputTokens = "decode_output_tokens"
            case prefillTokensPerSecond = "prefill_tokens_per_second"
            case decodeTokensPerSecond = "decode_tokens_per_second"
        }
    }

    let metrics: Metrics?
    /// Informational only: decoding must not fail if a future Splash changes or drops it.
    let schemaVersion: Int?
    let ready: Bool
    let maximumContextTokens: Int?
    let memoryPressure: String?
    let instance: Instance?
    let http: HTTP?
    let memoryActual: MemoryActual?
    let memoryGovernor: MemoryGovernor?

    init(schemaVersion: Int? = nil, ready: Bool, maximumContextTokens: Int?, memoryPressure: String?,
         instance: Instance? = nil, http: HTTP? = nil, memoryActual: MemoryActual? = nil,
         memoryGovernor: MemoryGovernor? = nil, metrics: Metrics? = nil) {
        self.metrics = metrics
        self.schemaVersion = schemaVersion
        self.ready = ready
        self.maximumContextTokens = maximumContextTokens
        self.memoryPressure = memoryPressure
        self.instance = instance
        self.http = http
        self.memoryActual = memoryActual
        self.memoryGovernor = memoryGovernor
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ready
        case maximumContextTokens = "maximum_context_tokens"
        case memoryPressure = "memory_pressure"
        case instance, http, metrics
        case memoryActual = "memory_actual"
        case memoryGovernor = "memory_governor"
    }
}

protocol SplashStatusRequest {
    func cancel()
}

protocol SplashStatusFetching {
    @discardableResult
    func fetchStatus(
        configuration: SplashConfiguration,
        apiKey: String?,
        completion: @escaping (Result<SplashStatus, Error>) -> Void
    ) -> SplashStatusRequest
}

enum SplashStatusClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid status URL."
        case .invalidResponse: return "Invalid status response."
        case .httpStatus(let code): return "Status request returned HTTP \(code)."
        }
    }
}

private struct NoopStatusRequest: SplashStatusRequest {
    func cancel() {}
}

extension URLSessionDataTask: SplashStatusRequest {}

/// Fetches one status snapshot. Scheduling and ownership stay in the process controller.
final class SplashStatusClient: SplashStatusFetching {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchStatus(
        configuration: SplashConfiguration,
        apiKey: String?,
        completion: @escaping (Result<SplashStatus, Error>) -> Void
    ) -> SplashStatusRequest {
        var components = URLComponents()
        components.scheme = "http"
        components.host = configuration.host == "0.0.0.0" ? "127.0.0.1" : configuration.host
        components.port = configuration.port
        components.path = "/status"
        guard let url = components.url else {
            DispatchQueue.main.async { completion(.failure(SplashStatusClientError.invalidURL)) }
            return NoopStatusRequest()
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 6
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let task = session.dataTask(with: request) { [decoder] data, response, error in
            let result: Result<SplashStatus, Error>
            if let error {
                result = .failure(error)
            } else if let response = response as? HTTPURLResponse {
                if !(200...299).contains(response.statusCode) {
                    result = .failure(SplashStatusClientError.httpStatus(response.statusCode))
                } else if let data {
                    result = Result { try decoder.decode(SplashStatus.self, from: data) }
                } else {
                    result = .failure(SplashStatusClientError.invalidResponse)
                }
            } else {
                result = .failure(SplashStatusClientError.invalidResponse)
            }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
        return task
    }
}
