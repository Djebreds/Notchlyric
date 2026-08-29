import Foundation

public protocol HTTPFetching: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int)
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int)
}

public struct URLSessionHTTP: HTTPFetching {
    public static let userAgent = "NotchLyrics/1.0 (personal use)"
    private let session: URLSession

    public init(timeout: TimeInterval = 8) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        try await run(request(url, method: "GET", headers: headers, body: nil))
    }

    public func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
        try await run(request(url, method: "POST", headers: headers, body: body))
    }

    private func request(_ url: URL, method: String,
                         headers: [String: String], body: Data?) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.httpBody = body
        r.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        return r
    }

    private func run(_ r: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: r)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
