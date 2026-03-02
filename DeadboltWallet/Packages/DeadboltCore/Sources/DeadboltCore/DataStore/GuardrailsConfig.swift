import Foundation

/// Configurable safety rules for agent-initiated transactions.
public struct GuardrailsConfig: Codable, Sendable {
    /// Max SOL allowed per single transaction.
    public var maxSOLPerTransaction: Double

    /// Max USD value allowed per single transaction.
    public var maxUSDPerTransaction: Double

    /// Max number of agent-initiated transactions per day.
    public var dailyTransactionLimit: Int

    /// Cumulative daily USD spend limit.
    public var dailyUSDLimit: Double

    /// Only allow swaps/sends involving these token mints. Empty = allow all.
    public var whitelistedTokens: [String]

    /// Only allow transactions touching these program IDs. Empty = allow all.
    public var whitelistedPrograms: [String]

    /// Minimum seconds between agent transactions (per agent).
    public var cooldownSeconds: Int

    public init(
        maxSOLPerTransaction: Double = 10.0,
        maxUSDPerTransaction: Double = 1000.0,
        dailyTransactionLimit: Int = 50,
        dailyUSDLimit: Double = 5000.0,
        whitelistedTokens: [String] = [],
        whitelistedPrograms: [String] = [],
        cooldownSeconds: Int = 5
    ) {
        self.maxSOLPerTransaction = maxSOLPerTransaction
        self.maxUSDPerTransaction = maxUSDPerTransaction
        self.dailyTransactionLimit = dailyTransactionLimit
        self.dailyUSDLimit = dailyUSDLimit
        self.whitelistedTokens = whitelistedTokens
        self.whitelistedPrograms = whitelistedPrograms
        self.cooldownSeconds = cooldownSeconds
    }

    /// Well-known Solana program IDs for default whitelist.
    public static let defaultWhitelistedPrograms: [String] = [
        "11111111111111111111111111111111",                         // System Program
        "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",            // Token Program
        "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL",           // Associated Token Program
        "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4",            // Jupiter v6
        "5ocnV1qiCgaQR8Jb8xWnVbApfaygJ8tNoZfgPwsgx9kx",          // Sanctum Router
        "ComputeBudget111111111111111111111111111111",              // Compute Budget
        "T1pyyaTNZsKv2WcRAB8oVnk93mLJw2XzjtVYqCsaHqt",            // Jito Tip Program
    ]

    /// Well-known token symbols for default whitelist.
    public static let defaultWhitelistedTokenSymbols: [String] = [
        "SOL", "USDC", "USDT"
    ]
}
