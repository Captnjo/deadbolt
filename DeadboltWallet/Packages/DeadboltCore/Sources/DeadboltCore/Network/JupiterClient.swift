import Foundation

/// Client for the Jupiter V6 Swap API (quote + swap-instructions endpoints).
public actor JupiterClient {
    private let httpClient: HTTPClient
    private let baseURL = URL(string: "https://api.jup.ag")!

    public init(httpClient: HTTPClient = HTTPClient()) {
        self.httpClient = httpClient
    }

    // MARK: - GET /swap/v1/quote

    /// Fetch a swap quote from Jupiter.
    /// - Parameters:
    ///   - inputMint: The mint address of the input token
    ///   - outputMint: The mint address of the output token
    ///   - amount: The input amount in smallest units (lamports / base units)
    ///   - slippageBps: Maximum slippage in basis points (e.g. 50 = 0.5%)
    /// - Returns: A `JupiterQuote` containing the best route
    public func getQuote(
        inputMint: String,
        outputMint: String,
        amount: UInt64,
        slippageBps: Int
    ) async throws -> JupiterQuote {
        let url = baseURL.appendingPathComponent("swap/v1/quote")
        let queryItems = [
            URLQueryItem(name: "inputMint", value: inputMint),
            URLQueryItem(name: "outputMint", value: outputMint),
            URLQueryItem(name: "amount", value: String(amount)),
            URLQueryItem(name: "slippageBps", value: String(slippageBps)),
        ]
        return try await httpClient.get(url: url, queryItems: queryItems)
    }

    // MARK: - POST /swap/v1/swap-instructions

    /// Fetch the swap instructions for a given quote.
    /// - Parameters:
    ///   - quote: The quote response from `getQuote`
    ///   - userPublicKey: The user's wallet public key (base58)
    /// - Returns: A `JupiterSwapInstructions` containing all instructions needed to execute the swap
    public func getSwapInstructions(
        quote: JupiterQuote,
        userPublicKey: String
    ) async throws -> JupiterSwapInstructions {
        let url = baseURL.appendingPathComponent("swap/v1/swap-instructions")
        let body = SwapInstructionsRequest(quoteResponse: quote, userPublicKey: userPublicKey)
        return try await httpClient.post(url: url, body: body)
    }
}

// MARK: - Request body for swap-instructions

private struct SwapInstructionsRequest: Encodable {
    let quoteResponse: JupiterQuote
    let userPublicKey: String
}
