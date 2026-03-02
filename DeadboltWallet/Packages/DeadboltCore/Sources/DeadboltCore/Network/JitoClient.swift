import Foundation

public actor JitoClient {
    private let session: URLSession
    private let transactionsURL = URL(string: "https://mainnet.block-engine.jito.wtf/api/v1/transactions")!
    private let bundlesURL = URL(string: "https://mainnet.block-engine.jito.wtf/api/v1/bundles")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Submit a single signed transaction to Jito for MEV-protected inclusion.
    /// Transaction must be base58-encoded (Jito uses base58, not base64).
    public func sendTransaction(serializedTransaction: Data) async throws -> String {
        let base58Tx = Base58.encode(serializedTransaction)

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "sendTransaction",
            "params": [base58Tx],
        ]

        var request = URLRequest(url: transactionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw SolanaError.httpError(statusCode: httpResponse.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SolanaError.decodingError("Invalid Jito response")
        }

        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown Jito error"
            throw SolanaError.rpcError(code: error["code"] as? Int ?? -1, message: message)
        }

        guard let result = json["result"] as? String else {
            throw SolanaError.decodingError("Missing signature in Jito response")
        }

        return result
    }

    /// Submit a bundle of transactions to Jito (e.g., swap + tip).
    /// Each transaction must be base58-encoded.
    public func sendBundle(serializedTransactions: [Data]) async throws -> String {
        let base58Txs = serializedTransactions.map { Base58.encode($0) }

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "sendBundle",
            "params": [base58Txs],
        ]

        var request = URLRequest(url: bundlesURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw SolanaError.httpError(statusCode: httpResponse.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SolanaError.decodingError("Invalid Jito bundle response")
        }

        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown Jito error"
            throw SolanaError.rpcError(code: error["code"] as? Int ?? -1, message: message)
        }

        guard let result = json["result"] as? String else {
            throw SolanaError.decodingError("Missing bundle ID in Jito response")
        }

        return result
    }

    /// Poll Jito for bundle status. Returns the bundle status including transaction signatures.
    /// Bundle statuses: "Invalid", "Pending", "Failed", "Landed"
    public func getBundleStatuses(bundleIds: [String]) async throws -> [JitoBundleStatus] {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getBundleStatuses",
            "params": [bundleIds],
        ]

        var request = URLRequest(url: bundlesURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw SolanaError.httpError(statusCode: httpResponse.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SolanaError.decodingError("Invalid Jito bundle status response")
        }

        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown Jito error"
            throw SolanaError.rpcError(code: error["code"] as? Int ?? -1, message: message)
        }

        guard let result = json["result"] as? [String: Any],
              let value = result["value"] as? [[String: Any]] else {
            return [] // No statuses yet
        }

        return value.compactMap { entry in
            guard let bundleId = entry["bundle_id"] as? String,
                  let status = entry["confirmation_status"] as? String else { return nil }
            let transactions = entry["transactions"] as? [String] ?? []
            return JitoBundleStatus(
                bundleId: bundleId,
                transactions: transactions,
                confirmationStatus: status
            )
        }
    }
}

/// Status of a Jito bundle.
public struct JitoBundleStatus: Sendable {
    public let bundleId: String
    public let transactions: [String]
    public let confirmationStatus: String // "Landed", "Pending", "Failed", "Invalid"
}
