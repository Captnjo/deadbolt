import Foundation

public actor HTTPClient {
    private let session: URLSession

    /// Default timeout for RPC calls (seconds).
    public static let rpcTimeout: TimeInterval = 10
    /// Default timeout for REST API calls (seconds).
    public static let restTimeout: TimeInterval = 15

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - JSON-RPC 2.0

    public func jsonRPC<T: Decodable>(
        url: URL,
        method: String,
        params: [Any] = [],
        timeout: TimeInterval = HTTPClient.rpcTimeout
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw SolanaError.httpError(statusCode: httpResponse.statusCode)
        }

        // Check for JSON-RPC error
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? -1
            let message = error["message"] as? String ?? "Unknown RPC error"
            throw SolanaError.rpcError(code: code, message: message)
        }

        let rpcResponse = try JSONDecoder().decode(RPCResponse<T>.self, from: data)
        guard let result = rpcResponse.result else {
            throw SolanaError.rpcError(code: -1, message: "RPC returned null result")
        }
        return result
    }

    // MARK: - REST GET

    public func get<T: Decodable>(url: URL, queryItems: [URLQueryItem] = [], timeout: TimeInterval = HTTPClient.restTimeout) async throws -> T {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SolanaError.decodingError("Invalid URL: \(url)")
        }
        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }

        guard let finalURL = components.url else {
            throw SolanaError.decodingError("Invalid URL components: \(components)")
        }

        var request = URLRequest(url: finalURL)
        request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw SolanaError.httpError(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - REST POST (JSON body)

    public func post<T: Decodable>(url: URL, body: some Encodable, timeout: TimeInterval = HTTPClient.restTimeout) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw SolanaError.httpError(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}
