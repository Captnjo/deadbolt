import Foundation

// MARK: - Helius DAS API response types

public struct HeliusAsset: Decodable, Sendable {
    public let id: String
    public let content: HeliusContent?
    public let ownership: HeliusOwnership?
    public let compression: HeliusCompression?

    public init(id: String, content: HeliusContent?, ownership: HeliusOwnership?, compression: HeliusCompression?) {
        self.id = id
        self.content = content
        self.ownership = ownership
        self.compression = compression
    }
}

public struct HeliusContent: Decodable, Sendable {
    public let metadata: HeliusMetadata?
    public let links: HeliusLinks?

    public init(metadata: HeliusMetadata?, links: HeliusLinks?) {
        self.metadata = metadata
        self.links = links
    }
}

public struct HeliusMetadata: Decodable, Sendable {
    public let name: String?
    public let symbol: String?
    public let description: String?

    public init(name: String?, symbol: String?, description: String?) {
        self.name = name
        self.symbol = symbol
        self.description = description
    }
}

public struct HeliusLinks: Decodable, Sendable {
    public let image: String?

    public init(image: String?) {
        self.image = image
    }
}

public struct HeliusOwnership: Decodable, Sendable {
    public let owner: String
    public let frozen: Bool?

    public init(owner: String, frozen: Bool?) {
        self.owner = owner
        self.frozen = frozen
    }
}

public struct HeliusCompression: Decodable, Sendable {
    public let compressed: Bool

    public init(compressed: Bool) {
        self.compressed = compressed
    }
}

// MARK: - App-level NFT model

public struct NFTAsset: Sendable, Equatable {
    public let mint: SolanaPublicKey
    public let name: String
    public let symbol: String
    public let imageURL: String?
    public let isCompressed: Bool

    public init(mint: SolanaPublicKey, name: String, symbol: String, imageURL: String?, isCompressed: Bool) {
        self.mint = mint
        self.name = name
        self.symbol = symbol
        self.imageURL = imageURL
        self.isCompressed = isCompressed
    }
}

// MARK: - Conversion

extension HeliusAsset {
    /// Convert a Helius DAS API asset to our app's NFTAsset model.
    /// Returns nil if the asset ID is not a valid public key or if metadata is missing.
    public func toNFTAsset() -> NFTAsset? {
        guard let mint = try? SolanaPublicKey(base58: id) else {
            return nil
        }

        let name = content?.metadata?.name ?? "Unknown"
        let symbol = content?.metadata?.symbol ?? ""
        let imageURL = content?.links?.image
        let isCompressed = compression?.compressed ?? false

        return NFTAsset(
            mint: mint,
            name: name,
            symbol: symbol,
            imageURL: imageURL,
            isCompressed: isCompressed
        )
    }
}

// MARK: - Helius getAssetsByOwner response envelope

public struct HeliusGetAssetsByOwnerResult: Decodable, Sendable {
    public let total: Int?
    public let limit: Int?
    public let page: Int?
    public let items: [HeliusAsset]
}
