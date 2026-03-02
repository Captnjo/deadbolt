import Foundation

/// Client for the Sanctum V1 API (quote, swap, and price endpoints).
/// Used for liquid staking operations (SOL → LST).
public actor SanctumClient {
    private let httpClient: HTTPClient
    private let baseURL = URL(string: "https://api.sanctum.so")!

    public init(httpClient: HTTPClient = HTTPClient()) {
        self.httpClient = httpClient
    }

    // MARK: - GET /v1/swap/quote

    /// Fetch a swap quote from Sanctum for staking SOL into an LST.
    ///
    /// - Parameters:
    ///   - input: The input token mint address (typically wrapped SOL)
    ///   - outputLstMint: The LST mint address to stake into (e.g. JitoSOL, mSOL)
    ///   - amount: The input amount in lamports
    ///   - mode: Swap mode, defaults to "ExactIn"
    /// - Returns: A `SanctumQuote` containing the output amount and fee info
    public func getQuote(
        input: String = LSTMint.wrappedSOL,
        outputLstMint: String,
        amount: UInt64,
        mode: String = "ExactIn"
    ) async throws -> SanctumQuote {
        let url = baseURL.appendingPathComponent("v1/swap/quote")
        let queryItems = [
            URLQueryItem(name: "input", value: input),
            URLQueryItem(name: "outputLstMint", value: outputLstMint),
            URLQueryItem(name: "amount", value: String(amount)),
            URLQueryItem(name: "mode", value: mode),
        ]
        return try await httpClient.get(url: url, queryItems: queryItems)
    }

    // MARK: - POST /v1/swap

    /// Execute a swap on Sanctum, returning a pre-built transaction.
    ///
    /// The returned transaction is a base64-encoded VersionedTransaction that
    /// needs to be deserialized and re-signed with the user's key before submission.
    ///
    /// - Parameters:
    ///   - input: The input token mint address (typically wrapped SOL)
    ///   - outputLstMint: The LST mint address to stake into
    ///   - amount: The input amount in lamports
    ///   - quotedAmount: The quoted output amount from `getQuote`
    ///   - signer: The user's wallet public key (base58)
    ///   - mode: Swap mode, defaults to "ExactIn"
    /// - Returns: A `SanctumSwapResponse` containing the base64-encoded transaction
    public func swap(
        input: String = LSTMint.wrappedSOL,
        outputLstMint: String,
        amount: UInt64,
        quotedAmount: String,
        signer: String,
        mode: String = "ExactIn"
    ) async throws -> SanctumSwapResponse {
        let url = baseURL.appendingPathComponent("v1/swap")
        let body = SanctumSwapRequest(
            input: input,
            outputLstMint: outputLstMint,
            amount: String(amount),
            quotedAmount: quotedAmount,
            signer: signer,
            mode: mode
        )
        return try await httpClient.post(url: url, body: body)
    }

    // MARK: - GET /v1/price

    /// Fetch the exchange rate between SOL and an LST from Sanctum.
    ///
    /// - Parameters:
    ///   - input: The input token mint address (typically wrapped SOL)
    ///   - output: The LST mint address to get the price for
    ///   - amount: The amount to price in smallest units (default: 1 SOL = 1_000_000_000 lamports)
    /// - Returns: A `SanctumPriceResponse` containing the output amount
    public func getPrice(
        input: String = LSTMint.wrappedSOL,
        output: String,
        amount: UInt64 = 1_000_000_000
    ) async throws -> SanctumPriceResponse {
        let url = baseURL.appendingPathComponent("v1/price")
        let queryItems = [
            URLQueryItem(name: "input", value: input),
            URLQueryItem(name: "output", value: output),
            URLQueryItem(name: "amount", value: String(amount)),
        ]
        return try await httpClient.get(url: url, queryItems: queryItems)
    }
}
