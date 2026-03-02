import Foundation

// MARK: - Quote Response

/// Sanctum V1 swap quote response from GET /v1/swap/quote
public struct SanctumQuote: Codable, Sendable {
    /// The input token mint address
    public let inAmount: String
    /// The output amount in smallest units
    public let outAmount: String
    /// Fee amount charged for the swap
    public let feeAmount: String
    /// Fee percentage as a string (e.g. "0.001")
    public let feePct: String
}

// MARK: - Swap Request

/// Request body for POST /v1/swap
public struct SanctumSwapRequest: Encodable, Sendable {
    /// Input token mint address (SOL wrapped mint for staking)
    public let input: String
    /// Output LST mint address
    public let outputLstMint: String
    /// Amount in smallest units (lamports for SOL)
    public let amount: String
    /// The quoted output amount (from quote response)
    public let quotedAmount: String
    /// The user's wallet public key (base58)
    public let signer: String
    /// Swap mode, typically "ExactIn"
    public let mode: String
}

// MARK: - Swap Response

/// Sanctum V1 swap response from POST /v1/swap
/// Returns a base64-encoded VersionedTransaction ready for signing
public struct SanctumSwapResponse: Codable, Sendable {
    /// Base64-encoded serialized VersionedTransaction
    public let tx: String
}

// MARK: - Price Response

/// Sanctum V1 price response from GET /v1/price
/// Returns the exchange rate between SOL and an LST
public struct SanctumPriceResponse: Codable, Sendable {
    /// The output amount for the given input amount
    public let amount: String
}

// MARK: - Common LST Mints

/// Well-known LST (Liquid Staking Token) mint addresses on Solana
public enum LSTMint {
    /// Wrapped SOL mint address
    public static let wrappedSOL = "So11111111111111111111111111111111111111112"
    /// JitoSOL mint address
    public static let jitoSOL = "J1toso1uCk3RLmjorhTtrVwY9HJ7X8V9yYac6Y7kGCPn"
    /// mSOL (Marinade) mint address
    public static let mSOL = "mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So"
    /// bSOL (BlazeStake) mint address
    public static let bSOL = "bSo13r4TkiE4KumL71LsHTPpL2euBYLFx6h9HP3piy1"
    /// bonkSOL mint address
    public static let bonkSOL = "BonK1YhkXEGLZzwtcvRTip3gAL9nCeQD7ppZBLXhtTs"
}
