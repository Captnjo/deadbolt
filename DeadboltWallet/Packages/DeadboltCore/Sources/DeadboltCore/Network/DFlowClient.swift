import Foundation

/// Client for the DFlow DEX aggregator API (imperative flow).
/// Returns a ready-to-sign transaction — no instruction assembly needed.
/// Requires an API key — generate one at https://pond.dflow.net/build/api-key
public actor DFlowClient {
    private let httpClient: HTTPClient
    private let apiKey: String
    private let baseURL = URL(string: "https://quote-api.dflow.net")!

    private var authHeaders: [String: String] {
        ["x-api-key": apiKey]
    }

    public init(apiKey: String, httpClient: HTTPClient = HTTPClient()) {
        self.apiKey = apiKey
        self.httpClient = httpClient
    }

    // MARK: - GET /order

    /// Fetch a swap order from DFlow. Returns a base64-encoded VersionedTransaction
    /// ready to be signed and submitted.
    ///
    /// - Parameters:
    ///   - inputMint: The mint address of the input token
    ///   - outputMint: The mint address of the output token
    ///   - amount: The input amount in smallest units (lamports / base units)
    ///   - slippageBps: Maximum slippage in basis points (e.g. 50 = 0.5%)
    ///   - userPublicKey: The user's wallet public key (base58)
    /// - Returns: A `DFlowOrder` containing the base64 transaction
    public func getOrder(
        inputMint: String,
        outputMint: String,
        amount: UInt64,
        slippageBps: Int,
        userPublicKey: String
    ) async throws -> DFlowOrder {
        let url = baseURL.appendingPathComponent("order")
        let queryItems = [
            URLQueryItem(name: "inputMint", value: inputMint),
            URLQueryItem(name: "outputMint", value: outputMint),
            URLQueryItem(name: "amount", value: String(amount)),
            URLQueryItem(name: "slippageBps", value: String(slippageBps)),
            URLQueryItem(name: "userPublicKey", value: userPublicKey),
        ]
        let response: DFlowOrderResponse = try await httpClient.get(
            url: url,
            queryItems: queryItems,
            headers: authHeaders
        )
        return DFlowOrder(transactionBase64: response.transaction)
    }
}
