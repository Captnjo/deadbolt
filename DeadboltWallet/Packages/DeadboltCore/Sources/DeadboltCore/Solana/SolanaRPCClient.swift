import Foundation

public actor SolanaRPCClient {
    private let rpcURL: URL
    private let httpClient: HTTPClient

    public init(rpcURL: URL, httpClient: HTTPClient = HTTPClient()) {
        self.rpcURL = rpcURL
        self.httpClient = httpClient
    }

    // MARK: - getBalance

    public func getBalance(address: String) async throws -> UInt64 {
        let result: BalanceResult = try await httpClient.jsonRPC(
            url: rpcURL,
            method: "getBalance",
            params: [address]
        )
        return result.value
    }

    // MARK: - getLatestBlockhash

    public func getLatestBlockhash() async throws -> BlockhashValue {
        let result: BlockhashResult = try await httpClient.jsonRPC(
            url: rpcURL,
            method: "getLatestBlockhash",
            params: [["commitment": "finalized"]]
        )
        return result.value
    }

    // MARK: - getTokenAccountsByOwner (jsonParsed)

    public func getTokenAccountsByOwner(address: String) async throws -> [TokenAccountEntry] {
        let result: TokenAccountsResult = try await httpClient.jsonRPC(
            url: rpcURL,
            method: "getTokenAccountsByOwner",
            params: [
                address,
                ["programId": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"],
                ["encoding": "jsonParsed"],
            ]
        )
        return result.value
    }

    // MARK: - getRecentPrioritizationFees

    /// Get recent prioritization fees to estimate a competitive priority fee.
    /// Returns fees from recent slots, sorted by slot descending.
    public func getRecentPrioritizationFees() async throws -> [PrioritizationFee] {
        let result: [PrioritizationFee] = try await httpClient.jsonRPC(
            url: rpcURL,
            method: "getRecentPrioritizationFees",
            params: []
        )
        return result
    }

    /// Suggest a priority fee in micro-lamports based on recent network activity.
    /// Uses the median of recent non-zero fees, with a floor of 1000 micro-lamports.
    public func suggestPriorityFee() async throws -> UInt64 {
        let fees = try await getRecentPrioritizationFees()
        let nonZero = fees.map(\.prioritizationFee).filter { $0 > 0 }.sorted()
        guard !nonZero.isEmpty else { return 1000 }
        let median = nonZero[nonZero.count / 2]
        return max(median, 1000)
    }

    // MARK: - sendTransaction

    /// Send a signed transaction (base64-encoded) and return the signature
    public func sendTransaction(
        encodedTransaction: String,
        skipPreflight: Bool = false,
        maxRetries: Int? = nil
    ) async throws -> String {
        var config: [String: Any] = [
            "encoding": "base64",
            "skipPreflight": skipPreflight,
            "preflightCommitment": "confirmed",
        ]
        if let maxRetries {
            config["maxRetries"] = maxRetries
        }

        let signature: String = try await httpClient.jsonRPC(
            url: rpcURL,
            method: "sendTransaction",
            params: [encodedTransaction, config]
        )
        return signature
    }

    // MARK: - getSignatureStatuses

    /// Poll confirmation status for one or more transaction signatures
    public func getSignatureStatuses(signatures: [String], searchTransactionHistory: Bool = false) async throws -> [SignatureStatus?] {
        let config: [String: Any] = [
            "searchTransactionHistory": searchTransactionHistory,
        ]
        let result: SignatureStatusesResult = try await httpClient.jsonRPC(
            url: rpcURL,
            method: "getSignatureStatuses",
            params: [signatures, config]
        )
        return result.value
    }

    // MARK: - getSignaturesForAddress

    /// Get recent transaction signatures for an address.
    /// - Parameters:
    ///   - address: The account address to query.
    ///   - limit: Maximum number of signatures to return (default 20, max 1000).
    ///   - before: Start searching backwards from this signature (for pagination).
    /// - Returns: An array of SignatureInfo, most recent first.
    public func getSignaturesForAddress(
        address: String,
        limit: Int = 20,
        before: String? = nil
    ) async throws -> [SignatureInfo] {
        var config: [String: Any] = [
            "limit": limit,
        ]
        if let before {
            config["before"] = before
        }
        let result: [SignatureInfo] = try await httpClient.jsonRPC(
            url: rpcURL,
            method: "getSignaturesForAddress",
            params: [address, config]
        )
        return result
    }

    // MARK: - simulateTransaction

    /// Simulate a transaction (base64-encoded) without submitting
    public func simulateTransaction(encodedTransaction: String) async throws -> SimulateValue {
        let result: SimulateResult = try await httpClient.jsonRPC(
            url: rpcURL,
            method: "simulateTransaction",
            params: [
                encodedTransaction,
                ["encoding": "base64", "commitment": "confirmed"],
            ]
        )
        return result.value
    }

    // MARK: - requestAirdrop (devnet/testnet only)

    /// Request an airdrop of lamports to the given address. Only works on devnet/testnet.
    public func requestAirdrop(address: String, lamports: UInt64) async throws -> String {
        let signature: String = try await httpClient.jsonRPC(
            url: rpcURL,
            method: "requestAirdrop",
            params: [address, lamports]
        )
        return signature
    }

    // MARK: - getTokenAccountBalance

    /// Check if a token account exists and get its balance.
    /// Returns nil if the account does not exist.
    public func getTokenAccountBalance(address: String) async throws -> TokenAmount? {
        do {
            let result: TokenAccountBalanceResult = try await httpClient.jsonRPC(
                url: rpcURL,
                method: "getTokenAccountBalance",
                params: [address]
            )
            return result.value
        } catch let error as SolanaError {
            // RPC returns error code -32602 for invalid/nonexistent token accounts
            if case .rpcError(_, _) = error {
                return nil
            }
            throw error
        }
    }

    // MARK: - getAccountInfo

    public func getAccountInfo<T: Decodable>(address: String, encoding: String = "jsonParsed") async throws -> AccountInfoValue<T>? {
        let result: AccountInfoResult<T> = try await httpClient.jsonRPC(
            url: rpcURL,
            method: "getAccountInfo",
            params: [
                address,
                ["encoding": encoding],
            ]
        )
        return result.value
    }

    // MARK: - getAddressLookupTable

    /// Fetch and deserialize an Address Lookup Table from the network.
    public func getAddressLookupTable(address: String) async throws -> AddressLookupTable {
        let accountInfo: AccountInfoValue<[String]>? = try await getAccountInfo(address: address, encoding: "base64")

        guard let info = accountInfo else {
            throw SolanaError.decodingError("Address lookup table account not found: \(address)")
        }

        // base64 encoding returns data as [base64String, "base64"]
        guard let base64String = info.data.first,
              let data = Data(base64Encoded: base64String) else {
            throw SolanaError.decodingError("Failed to decode base64 ALT data for: \(address)")
        }

        let key = try SolanaPublicKey(base58: address)
        return try AddressLookupTable.deserialize(key: key, data: data)
    }
}
