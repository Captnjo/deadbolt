import Foundation

// MARK: - Helius Enhanced Transactions API types

/// A parsed transaction from the Helius Enhanced Transactions API.
public struct HeliusEnhancedTransaction: Decodable, Sendable {
    /// Human-readable description of the transaction.
    public let description: String
    /// Transaction type (e.g., "TRANSFER", "SWAP", "NFT_SALE").
    public let type: String
    /// Source protocol or program (e.g., "SYSTEM_PROGRAM", "JUPITER").
    public let source: String
    /// Transaction fee in lamports.
    public let fee: Int
    /// The fee payer's address.
    public let feePayer: String
    /// Transaction signature.
    public let signature: String
    /// Slot number.
    public let slot: Int
    /// Unix timestamp.
    public let timestamp: Int
    /// Native SOL transfers in this transaction.
    public let nativeTransfers: [HeliusNativeTransfer]?
    /// SPL token transfers in this transaction.
    public let tokenTransfers: [HeliusTokenTransfer]?

    public init(
        description: String,
        type: String,
        source: String,
        fee: Int,
        feePayer: String,
        signature: String,
        slot: Int,
        timestamp: Int,
        nativeTransfers: [HeliusNativeTransfer]?,
        tokenTransfers: [HeliusTokenTransfer]?
    ) {
        self.description = description
        self.type = type
        self.source = source
        self.fee = fee
        self.feePayer = feePayer
        self.signature = signature
        self.slot = slot
        self.timestamp = timestamp
        self.nativeTransfers = nativeTransfers
        self.tokenTransfers = tokenTransfers
    }
}

/// A native SOL transfer within a transaction.
public struct HeliusNativeTransfer: Decodable, Sendable, Equatable {
    /// The sender's account address.
    public let fromUserAccount: String
    /// The recipient's account address.
    public let toUserAccount: String
    /// Amount in lamports.
    public let amount: Int

    public init(fromUserAccount: String, toUserAccount: String, amount: Int) {
        self.fromUserAccount = fromUserAccount
        self.toUserAccount = toUserAccount
        self.amount = amount
    }
}

/// An SPL token transfer within a transaction.
public struct HeliusTokenTransfer: Decodable, Sendable, Equatable {
    /// The sender's wallet address.
    public let fromUserAccount: String?
    /// The recipient's wallet address.
    public let toUserAccount: String?
    /// The sender's token account address.
    public let fromTokenAccount: String?
    /// The recipient's token account address.
    public let toTokenAccount: String?
    /// Token amount (as a decimal number).
    public let tokenAmount: Double
    /// The token's mint address.
    public let mint: String

    public init(
        fromUserAccount: String?,
        toUserAccount: String?,
        fromTokenAccount: String?,
        toTokenAccount: String?,
        tokenAmount: Double,
        mint: String
    ) {
        self.fromUserAccount = fromUserAccount
        self.toUserAccount = toUserAccount
        self.fromTokenAccount = fromTokenAccount
        self.toTokenAccount = toTokenAccount
        self.tokenAmount = tokenAmount
        self.mint = mint
    }
}

// MARK: - Request body for Enhanced Transactions API

/// Request body for the Helius Enhanced Transactions API.
struct HeliusEnhancedTransactionsRequest: Encodable {
    let transactions: [String]
}
