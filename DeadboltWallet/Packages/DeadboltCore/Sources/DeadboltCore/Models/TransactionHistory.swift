import Foundation

// MARK: - Transaction Type

/// Classification of a transaction's type.
public enum TransactionType: String, Sendable, Equatable {
    case transfer = "TRANSFER"
    case swap = "SWAP"
    case stake = "STAKE"
    case nftTransfer = "NFT_TRANSFER"
    case unknown = "UNKNOWN"

    /// Initialize from a Helius transaction type string.
    public init(heliusType: String) {
        switch heliusType.uppercased() {
        case "TRANSFER":
            self = .transfer
        case "SWAP":
            self = .swap
        case "STAKE", "UNSTAKE":
            self = .stake
        case "NFT_TRANSFER", "NFT_SALE", "NFT_LISTING", "NFT_MINT", "NFT_BID",
             "NFT_CANCEL_LISTING", "NFT_BID_CANCELLED", "COMPRESSED_NFT_TRANSFER",
             "COMPRESSED_NFT_MINT":
            self = .nftTransfer
        default:
            self = .unknown
        }
    }
}

// MARK: - Transaction History Entry

/// A single entry in the transaction history.
public struct TransactionHistoryEntry: Sendable, Equatable {
    /// The transaction signature.
    public let signature: String

    /// The classified transaction type.
    public let type: TransactionType

    /// Human-readable description from Helius.
    public let description: String

    /// When the transaction was confirmed.
    public let timestamp: Date

    /// Human-readable amount string (e.g., "0.5 SOL", "100 USDC").
    public let amount: String?

    /// Native SOL transfers in this transaction.
    public let nativeTransfers: [HeliusNativeTransfer]

    /// SPL token transfers in this transaction.
    public let tokenTransfers: [HeliusTokenTransfer]

    public init(
        signature: String,
        type: TransactionType,
        description: String,
        timestamp: Date,
        amount: String?,
        nativeTransfers: [HeliusNativeTransfer],
        tokenTransfers: [HeliusTokenTransfer]
    ) {
        self.signature = signature
        self.type = type
        self.description = description
        self.timestamp = timestamp
        self.amount = amount
        self.nativeTransfers = nativeTransfers
        self.tokenTransfers = tokenTransfers
    }
}

// MARK: - Conversion from Helius Enhanced Transaction

extension TransactionHistoryEntry {
    /// Create a TransactionHistoryEntry from a Helius Enhanced Transaction.
    public init(from helius: HeliusEnhancedTransaction) {
        self.signature = helius.signature
        self.type = TransactionType(heliusType: helius.type)
        self.description = helius.description
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(helius.timestamp))

        let nativeTransfers = helius.nativeTransfers ?? []
        let tokenTransfers = helius.tokenTransfers ?? []

        self.nativeTransfers = nativeTransfers
        self.tokenTransfers = tokenTransfers

        // Build a human-readable amount string
        self.amount = Self.buildAmountString(
            nativeTransfers: nativeTransfers,
            tokenTransfers: tokenTransfers,
            feePayer: helius.feePayer
        )
    }

    /// Build a human-readable amount string from transfers.
    private static func buildAmountString(
        nativeTransfers: [HeliusNativeTransfer],
        tokenTransfers: [HeliusTokenTransfer],
        feePayer: String
    ) -> String? {
        // Prefer token transfers if present
        if let firstToken = tokenTransfers.first {
            let amount = firstToken.tokenAmount
            let mint = firstToken.mint
            // Use short mint address as fallback symbol
            let symbol = shortMint(mint)
            return String(format: "%.6g", amount) + " " + symbol
        }

        // Sum non-fee native transfers
        let nonFeeTransfers = nativeTransfers.filter { $0.amount > 0 }
        if let firstNative = nonFeeTransfers.first {
            let solAmount = Double(firstNative.amount) / 1_000_000_000.0
            return String(format: "%.9g", solAmount) + " SOL"
        }

        return nil
    }

    private static func shortMint(_ mint: String) -> String {
        guard mint.count > 8 else { return mint }
        let start = mint.prefix(4)
        let end = mint.suffix(4)
        return "\(start)...\(end)"
    }
}
