import Foundation

// MARK: - Quote Response

/// Jupiter V6 quote response from GET /v6/quote
public struct JupiterQuote: Codable, Sendable {
    public let inputMint: String
    public let inAmount: String
    public let outputMint: String
    public let outAmount: String
    public let otherAmountThreshold: String
    public let swapMode: String
    public let slippageBps: Int
    public let priceImpactPct: String?
    public let routePlan: [JupiterRoutePlanStep]
}

/// A single step in the Jupiter route plan
public struct JupiterRoutePlanStep: Codable, Sendable {
    public let swapInfo: JupiterSwapInfo
    public let percent: Int
}

/// Swap info for a single AMM hop
public struct JupiterSwapInfo: Codable, Sendable {
    public let ammKey: String
    public let label: String?
    public let inputMint: String
    public let outputMint: String
    public let inAmount: String
    public let outAmount: String
    public let feeAmount: String
    public let feeMint: String
}

// MARK: - Swap Instructions Response

/// Jupiter V6 swap-instructions response from POST /v6/swap-instructions
public struct JupiterSwapInstructions: Decodable, Sendable {
    public let tokenLedgerInstruction: JupiterInstructionData?
    public let computeBudgetInstructions: [JupiterInstructionData]
    public let setupInstructions: [JupiterInstructionData]
    public let swapInstruction: JupiterInstructionData
    public let cleanupInstruction: JupiterInstructionData?
    public let addressLookupTableAddresses: [String]
}

/// A single instruction as returned by Jupiter API (base64 data, base58 program ID)
public struct JupiterInstructionData: Decodable, Sendable {
    public let programId: String
    public let accounts: [JupiterAccountData]
    public let data: String // base64 encoded
}

/// Account metadata in Jupiter instruction response
public struct JupiterAccountData: Decodable, Sendable {
    public let pubkey: String
    public let isSigner: Bool
    public let isWritable: Bool
}
