import Foundation

/// A Solana versioned transaction supporting both legacy and v0 message formats.
public struct VersionedTransaction: Sendable {
    public let message: VersionedMessage
    public private(set) var signatures: [Data] // 64 bytes each

    /// Create an unsigned versioned transaction from a message.
    /// Pre-allocates empty signature slots for each required signer.
    public init(message: VersionedMessage) {
        self.message = message
        let numSigners: Int
        switch message {
        case .legacy(let msg):
            numSigners = Int(msg.header.numRequiredSignatures)
        case .v0(let msg):
            numSigners = Int(msg.header.numRequiredSignatures)
        }
        self.signatures = Array(
            repeating: Data(repeating: 0, count: 64),
            count: numSigners
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
        let accountKeys: [SolanaPublicKey]
        let numSigners: Int

        switch message {
        case .legacy(let msg):
            accountKeys = msg.accountKeys
            numSigners = Int(msg.header.numRequiredSignatures)
        case .v0(let msg):
            accountKeys = msg.accountKeys
            numSigners = Int(msg.header.numRequiredSignatures)
        }

        guard let signerIndex = accountKeys.prefix(numSigners).firstIndex(of: signer.publicKey) else {
            throw SolanaError.decodingError("Signer \(signer.publicKey) not found in required signers")
        }

        signatures[signerIndex] = signature
    }

    /// Initialize a VersionedTransaction with a pre-existing message and signatures.
    /// Used during deserialization when signatures are already present.
    public init(message: VersionedMessage, signatures: [Data]) {
        self.message = message
        self.signatures = signatures
    }

    /// Deserialize a VersionedTransaction from its wire format bytes.
    ///
    /// Wire format:
    /// - compact-u16: signature count
    /// - N * 64 bytes: signatures
    /// - remaining bytes: serialized VersionedMessage (legacy or v0)
    ///
    /// - Parameter data: The serialized transaction data
    /// - Returns: A deserialized `VersionedTransaction`
    public static func deserialize(from data: Data) throws -> VersionedTransaction {
        var offset = 0

        // Read signature count (compact-u16)
        let (sigCount, sigCountBytes) = try CompactU16.decode(data, offset: offset)
        offset += sigCountBytes

        // Read signatures (64 bytes each)
        var signatures: [Data] = []
        for _ in 0..<sigCount {
            guard offset + 64 <= data.count else {
                throw SolanaError.decodingError("Not enough bytes for signature")
            }
            signatures.append(Data(data[offset..<offset + 64]))
            offset += 64
        }

        // Deserialize the message (rest of the data)
        let message = try VersionedMessage.deserialize(from: data, offset: &offset)

        return VersionedTransaction(message: message, signatures: signatures)
    }

    /// Serialize the full transaction to wire format:
    /// compact-u16 sig count + signatures + serialized message.
    public func serialize() -> Data {
        var data = Data()

        // Signature count (compact-u16)
        data.append(contentsOf: CompactU16.encode(UInt16(signatures.count)))

        // Signatures (64 bytes each)
        for sig in signatures {
            data.append(sig)
        }

        // Serialized message (includes version prefix for v0)
        data.append(message.serialize())

        return data
    }

    /// Serialize to base64 for RPC submission.
    public func serializeBase64() -> String {
        serialize().base64EncodedString()
    }
}
