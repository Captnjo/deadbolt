import Foundation

/// Service for fetching and caching NFT assets using the Helius DAS API.
public actor NFTService {
    private let heliusClient: HeliusClient
    private var cache: [String: [NFTAsset]] = [:]

    public init(heliusClient: HeliusClient) {
        self.heliusClient = heliusClient
    }

    /// Fetch NFTs owned by the given address.
    /// Results are cached per owner address; call `clearCache()` to refresh.
    public func fetchNFTs(owner: String) async throws -> [NFTAsset] {
        if let cached = cache[owner] {
            return cached
        }

        let assets = try await heliusClient.getAssetsByOwner(owner: owner)
        let nfts = assets.compactMap { $0.toNFTAsset() }

        cache[owner] = nfts
        return nfts
    }

    /// Clear the cached NFTs for a specific owner, or all owners if nil.
    public func clearCache(owner: String? = nil) {
        if let owner {
            cache.removeValue(forKey: owner)
        } else {
            cache.removeAll()
        }
    }

    /// Check if a token account entry represents an NFT.
    /// An NFT has decimals=0 and amount="1".
    public static func isNFT(tokenAccount: TokenAccountEntry) -> Bool {
        let info = tokenAccount.account.data.parsed.info
        return info.tokenAmount.decimals == 0 && info.tokenAmount.amount == "1"
    }
}
