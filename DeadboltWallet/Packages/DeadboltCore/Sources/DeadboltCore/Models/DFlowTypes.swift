import Foundation

// MARK: - DFlow Order Response

/// DFlow order response from GET /order
/// Returns a ready-to-sign versioned transaction as base64.
public struct DFlowOrderResponse: Decodable, Sendable {
    public let transaction: String // base64-encoded VersionedTransaction
}

// MARK: - DFlow Order

/// Parsed DFlow order holding the raw base64 transaction string.
public struct DFlowOrder: Sendable {
    public let transactionBase64: String

    public init(transactionBase64: String) {
        self.transactionBase64 = transactionBase64
    }
}
