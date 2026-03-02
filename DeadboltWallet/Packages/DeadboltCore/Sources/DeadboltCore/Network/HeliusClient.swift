import Foundation

/// Client for the Helius DAS (Digital Asset Standard) and Enhanced Transactions APIs.
/// Uses JSON-RPC 2.0 over the Helius RPC endpoint for DAS,
/// and REST POST to api.helius.xyz for Enhanced Transactions.
public actor HeliusClient {
    private let apiKey: String
    private let httpClient: HTTPClient
    /// RPC endpoint — API key passed via query param (required by Helius RPC).
    private let baseURL: URL
    /// Enhanced Transactions API — API key passed via query param (required by Helius REST).
    private let enhancedAPIBaseURL: URL

    public init(apiKey: String, httpClient: HTTPClient = HTTPClient()) {
        self.apiKey = apiKey
        self.httpClient = httpClient
        // Helius requires the API key in the URL for RPC and REST endpoints
        self.baseURL = URL(string: "https://mainnet.helius-rpc.com/?api-key=\(apiKey)")!
        self.enhancedAPIBaseURL = URL(string: "https://api.helius.xyz/v0/transactions/?api-key=\(apiKey)")!
    }

    /// Fetch non-fungible assets (NFTs) owned by the given address using the Helius DAS API.
    /// - Parameters:
    ///   - owner: The wallet address to query.
    ///   - page: Page number (1-indexed). Defaults to 1.
    ///   - limit: Maximum number of results per page. Defaults to 1000.
    /// - Returns: An array of HeliusAsset structs representing the owner's NFTs.
    public func getAssetsByOwner(
        owner: String,
        page: Int = 1,
        limit: Int = 1000
    ) async throws -> [HeliusAsset] {
        let params: [String: Any] = [
            "ownerAddress": owner,
            "page": page,
            "limit": limit,
            "displayOptions": ["showFungible": false],
        ]

        let result: HeliusGetAssetsByOwnerResult = try await httpClient.jsonRPC(
            url: baseURL,
            method: "getAssetsByOwner",
            params: [params]
        )

        return result.items
    }

    // MARK: - Enhanced Transactions API

    /// Fetch parsed/enhanced transaction details from the Helius Enhanced Transactions API.
    ///
    /// - Parameter signatures: An array of transaction signatures to look up (max 100).
    /// - Returns: An array of HeliusEnhancedTransaction with parsed details.
    public func getEnhancedTransactions(signatures: [String]) async throws -> [HeliusEnhancedTransaction] {
        let requestBody = HeliusEnhancedTransactionsRequest(transactions: signatures)
        let result: [HeliusEnhancedTransaction] = try await httpClient.post(
            url: enhancedAPIBaseURL,
            body: requestBody
        )
        return result
    }
}
