import Foundation

// MARK: - Intent Type Enum

enum IntentType: String, Codable, Sendable {
    case sendSol = "send_sol"
    case sendToken = "send_token"
    case swap = "swap"
    case stake = "stake"
    case signMessage = "sign_message"
    case createWallet = "create_wallet"
    case batch = "batch"
}

// MARK: - Intent Request

struct IntentRequest: Codable, Sendable {
    let type: IntentType
    let params: IntentParams
    let metadata: IntentMetadata?
}

// MARK: - Intent Params (tagged union via coding)

enum IntentParams: Codable, Sendable {
    case sendSol(SendSOLParams)
    case sendToken(SendTokenParams)
    case swap(SwapParams)
    case stake(StakeParams)
    case signMessage(SignMessageParams)
    case createWallet(CreateWalletParams)
    case batch(BatchParams)

    init(from decoder: Decoder) throws {
        // IntentParams should only be decoded via IntentRequest.init(from:) which dispatches by type tag.
        // This fallback decoder should never be invoked directly.
        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "IntentParams must be decoded via IntentRequest (type-tagged dispatch)")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .sendSol(let v): try container.encode(v)
        case .sendToken(let v): try container.encode(v)
        case .swap(let v): try container.encode(v)
        case .stake(let v): try container.encode(v)
        case .signMessage(let v): try container.encode(v)
        case .createWallet(let v): try container.encode(v)
        case .batch(let v): try container.encode(v)
        }
    }
}

// MARK: - Param Structs

struct SendSOLParams: Codable, Sendable {
    let recipient: String
    let amount: UInt64 // lamports
}

struct SendTokenParams: Codable, Sendable {
    let recipient: String
    let mint: String
    let amount: UInt64
    let decimals: Int?
}

struct SwapParams: Codable, Sendable {
    let inputMint: String
    let outputMint: String
    let amount: UInt64
    let slippageBps: Int?

    enum CodingKeys: String, CodingKey {
        case inputMint = "input_mint"
        case outputMint = "output_mint"
        case amount
        case slippageBps = "slippage_bps"
    }
}

struct StakeParams: Codable, Sendable {
    let lstMint: String
    let amount: UInt64 // lamports

    enum CodingKeys: String, CodingKey {
        case lstMint = "lst_mint"
        case amount
    }
}

struct SignMessageParams: Codable, Sendable {
    let message: String
}

struct CreateWalletParams: Codable, Sendable {
    let name: String?
    let source: String? // "hot" or "hardware"
}

struct BatchParams: Codable, Sendable {
    let intents: [IntentRequest]
}

// MARK: - Intent Metadata

struct IntentMetadata: Codable, Sendable {
    let agentId: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case reason
    }
}

// MARK: - Intent Response

struct IntentResponse: Codable, Sendable {
    let requestId: String
    let status: IntentStatus
    let preview: IntentPreview?
    let signature: String?
    let slot: UInt64?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case status
        case preview
        case signature
        case slot
        case error
    }
}

// MARK: - Intent Status

enum IntentStatus: String, Codable, Sendable {
    case pendingApproval = "pending_approval"
    case building = "building"
    case signing = "signing"
    case submitted = "submitted"
    case confirmed = "confirmed"
    case rejected = "rejected"
    case failed = "failed"
}

// MARK: - Intent Preview

struct IntentPreview: Codable, Sendable {
    let action: String
    let fees: FeesPreview?
    let warnings: [String]
    let simulation: SimulationResult?
    let balanceChanges: [IntentBalanceChange]?

    enum CodingKeys: String, CodingKey {
        case action
        case fees
        case warnings
        case simulation
        case balanceChanges = "balance_changes"
    }
}

struct FeesPreview: Codable, Sendable {
    let base: UInt64
    let priority: UInt64
    let tip: UInt64

    var totalLamports: UInt64 { base + priority + tip }
    var totalSOL: Double { Double(totalLamports) / 1_000_000_000.0 }
}

struct SimulationResult: Codable, Sendable {
    let success: Bool
    let computeUnitsUsed: UInt64?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case computeUnitsUsed = "compute_units_used"
        case error
    }
}

struct IntentBalanceChange: Codable, Sendable {
    let token: String
    let amount: String // signed, e.g. "-1.00084" or "+138.50"
}

// MARK: - Error Response

struct APIErrorResponse: Codable, Sendable {
    let error: String
    let code: Int
}

// MARK: - Custom Decoding for IntentRequest

// IntentRequest needs custom decoding to dispatch params based on type.
extension IntentRequest {
    private enum CodingKeys: String, CodingKey {
        case type
        case params
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(IntentType.self, forKey: .type)
        self.type = type
        self.metadata = try container.decodeIfPresent(IntentMetadata.self, forKey: .metadata)

        switch type {
        case .sendSol:
            self.params = .sendSol(try container.decode(SendSOLParams.self, forKey: .params))
        case .sendToken:
            self.params = .sendToken(try container.decode(SendTokenParams.self, forKey: .params))
        case .swap:
            self.params = .swap(try container.decode(SwapParams.self, forKey: .params))
        case .stake:
            self.params = .stake(try container.decode(StakeParams.self, forKey: .params))
        case .signMessage:
            self.params = .signMessage(try container.decode(SignMessageParams.self, forKey: .params))
        case .createWallet:
            self.params = .createWallet(try container.decode(CreateWalletParams.self, forKey: .params))
        case .batch:
            self.params = .batch(try container.decode(BatchParams.self, forKey: .params))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(params, forKey: .params)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}
