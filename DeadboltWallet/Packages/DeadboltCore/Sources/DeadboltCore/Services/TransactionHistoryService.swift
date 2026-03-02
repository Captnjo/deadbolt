import Foundation

/// Service for fetching and caching transaction history.
///
/// Uses the Solana RPC `getSignaturesForAddress` to get recent signatures,
/// then the Helius Enhanced Transactions API for parsed details.
public actor TransactionHistoryService {
    private let rpcClient: SolanaRPCClient
    private let heliusClient: HeliusClient

    /// In-memory cache: wallet address -> cached entries.
    private var cache: [String: CachedHistory] = [:]

    /// How long cached entries remain valid (5 minutes).
    private let cacheTTL: TimeInterval = 300

    public init(rpcClient: SolanaRPCClient, heliusClient: HeliusClient) {
        self.rpcClient = rpcClient
        self.heliusClient = heliusClient
    }

    /// Fetch transaction history for a wallet address.
    ///
    /// - Parameters:
    ///   - address: The wallet address to query.
    ///   - limit: Maximum number of transactions to return (default 20).
    ///   - forceRefresh: If true, bypass the cache and fetch fresh data.
    /// - Returns: An array of TransactionHistoryEntry, most recent first.
    public func getHistory(
        for address: String,
        limit: Int = 20,
        forceRefresh: Bool = false
    ) async throws -> [TransactionHistoryEntry] {
        // Check cache
        if !forceRefresh, let cached = cache[address], !cached.isExpired(ttl: cacheTTL) {
            return cached.entries
        }

        // 1. Get recent signatures from RPC
        let signatureInfos = try await rpcClient.getSignaturesForAddress(
            address: address,
            limit: limit
        )

        guard !signatureInfos.isEmpty else {
            let empty: [TransactionHistoryEntry] = []
            cache[address] = CachedHistory(entries: empty)
            return empty
        }

        let signatures = signatureInfos.map(\.signature)

        // 2. Get enhanced transaction details from Helius (batch, max 100)
        let enhanced = try await heliusClient.getEnhancedTransactions(signatures: signatures)

        // 3. Convert to history entries
        let entries = enhanced.map { TransactionHistoryEntry(from: $0) }

        // 4. Cache the result
        cache[address] = CachedHistory(entries: entries)

        return entries
    }

    /// Clear the cache for a specific address, or all addresses if nil.
    public func clearCache(for address: String? = nil) {
        if let address {
            cache.removeValue(forKey: address)
        } else {
            cache.removeAll()
        }
    }
}

// MARK: - Cache Entry

private struct CachedHistory {
    let entries: [TransactionHistoryEntry]
    let fetchedAt: Date

    init(entries: [TransactionHistoryEntry]) {
        self.entries = entries
        self.fetchedAt = Date()
    }

    func isExpired(ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(fetchedAt) > ttl
    }
}
