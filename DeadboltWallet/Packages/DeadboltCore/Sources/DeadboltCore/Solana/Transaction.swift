import Foundation

/// A Solana legacy transaction: signature(s) + serialized message.
public struct Transaction: Sendable {
    public let message: Message
    public private(set) var signatures: [Data] // 64 bytes each

    /// Create an unsigned transaction from a message.
    /// Pre-allocates empty signature slots for each required signer.
    public init(message: Message) {
        self.message = message
        self.signatures = Array(
            repeating: Data(repeating: 0, count: 64),
            count: Int(message.header.numRequiredSignatures)
        )
    }

    /// Sign the transaction with a signer. The signer's public key must match
    /// one of the required signers in the message's account keys.
    public mutating func sign(with signer: TransactionSigner) async throws {
        let messageData = message.serialize()
        let signature = try await signer.sign(message: messageData)

        guard signature.count == 64 else {
            throw SolanaError.decodingError("Invalid signature length: \(signature.count), expected 64")
        }

        // Find the signer's index in the account keys
        let numSigners = Int(message.header.numRequiredSignatures)
        guard let signerIndex = message.accountKeys.prefix(numSigners).firstIndex(of: signer.publicKey) else {
            throw SolanaError.decodingError("Signer \(signer.publicKey) not found in required signers")
        }

        signatures[signerIndex] = signature
    }

    /// Serialize the full transaction to wire format: compact-u16 sig count + signatures + serialized message.
    public func serialize() -> Data {
        var data = Data()

        // Signature count (compact-u16)
        data.append(contentsOf: CompactU16.encode(UInt16(signatures.count)))

        // Signatures (64 bytes each)
        for sig in signatures {
            data.append(sig)
        }

        // Serialized message
        data.append(message.serialize())

        return data
    }

    /// Serialize to base64 for RPC submission.
    public func serializeBase64() -> String {
        serialize().base64EncodedString()
    }
}
