import Foundation

// MARK: - JSON-RPC envelope

public struct RPCResponse<T: Decodable>: Decodable {
    public let jsonrpc: String
    public let id: Int
    public let result: T?
}

// MARK: - getBalance

public struct BalanceResult: Decodable {
    public let value: UInt64
}

// MARK: - getLatestBlockhash

public struct BlockhashResult: Decodable {
    public let value: BlockhashValue
}

public struct BlockhashValue: Decodable {
    public let blockhash: String
    public let lastValidBlockHeight: UInt64
}

// MARK: - getAccountInfo

public struct AccountInfoResult<T: Decodable>: Decodable {
    public let value: AccountInfoValue<T>?
}

public struct AccountInfoValue<T: Decodable>: Decodable {
    public let data: T
    public let executable: Bool
    public let lamports: UInt64
    public let owner: String
}

// MARK: - getTokenAccountsByOwner (jsonParsed)

public struct TokenAccountsResult: Decodable {
    public let value: [TokenAccountEntry]
}

public struct TokenAccountEntry: Decodable {
    public let pubkey: String
    public let account: TokenAccountData
}

public struct TokenAccountData: Decodable {
    public let data: TokenAccountParsed
    public let lamports: UInt64
}

public struct TokenAccountParsed: Decodable {
    public let parsed: TokenAccountInfo
    public let program: String
}

public struct TokenAccountInfo: Decodable {
    public let info: TokenAccountInfoData
    public let type: String
}

public struct TokenAccountInfoData: Decodable {
    public let mint: String
    public let owner: String
    public let tokenAmount: TokenAmount
}

public struct TokenAmount: Decodable {
    public let amount: String
    public let decimals: Int
    public let uiAmount: Double?
    public let uiAmountString: String
}

// MARK: - getTokenAccountBalance

public struct TokenAccountBalanceResult: Decodable {
    public let value: TokenAmount
}

// MARK: - getRecentPrioritizationFees

public struct PrioritizationFee: Decodable {
    public let slot: UInt64
    public let prioritizationFee: UInt64
}

// MARK: - sendTransaction (returns signature string directly)

// MARK: - getSignatureStatuses

public struct SignatureStatusesResult: Decodable {
    public let value: [SignatureStatus?]
}

public struct SignatureStatus: Decodable {
    public let slot: UInt64?
    public let confirmations: UInt64?
    public let err: SignatureError?
    public let confirmationStatus: String? // "processed", "confirmed", "finalized"
}

public enum SignatureError: Decodable, Sendable {
    case string(String)
    case object([String: String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let obj = try? container.decode([String: String].self) {
            self = .object(obj)
        } else {
            self = .string("Unknown transaction error")
        }
    }
}

// MARK: - getSignaturesForAddress

public struct SignatureInfo: Decodable, Sendable {
    public let signature: String
    public let slot: UInt64
    public let blockTime: Int?
    public let err: SignatureError?
    public let memo: String?
    public let confirmationStatus: String?
}

// MARK: - simulateTransaction

public struct SimulateResult: Decodable {
    public let value: SimulateValue
}

public struct SimulateValue: Decodable {
    public let err: SimulateError?
    public let logs: [String]?
    public let unitsConsumed: UInt64?
}

public enum SimulateError: Decodable {
    case string(String)
    case object([String: String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let obj = try? container.decode([String: String].self) {
            self = .object(obj)
        } else {
            self = .string("Unknown simulation error")
        }
    }
}
