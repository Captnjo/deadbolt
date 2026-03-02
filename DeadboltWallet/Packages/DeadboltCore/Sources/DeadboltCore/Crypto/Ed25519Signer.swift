import Foundation
import CryptoKit

/// Protocol for anything that can sign Solana transaction messages
public protocol TransactionSigner: Sendable {
    var publicKey: SolanaPublicKey { get }
    func sign(message: Data) async throws -> Data
}

/// Software signer using CryptoKit Curve25519
public final class SoftwareSigner: TransactionSigner, @unchecked Sendable {
    private let privateKey: Curve25519.Signing.PrivateKey
    public let publicKey: SolanaPublicKey

    /// Initialize from a 32-byte Ed25519 seed
    public init(seed: Data) throws {
        self.privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        let pubData = Data(privateKey.publicKey.rawRepresentation)
        self.publicKey = try SolanaPublicKey(data: pubData)
    }

    /// Initialize from a Keypair, verifying the public key matches
    public init(keypair: Keypair) throws {
        self.privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keypair.seed)
        let derivedPubData = Data(privateKey.publicKey.rawRepresentation)
        let derivedKey = try SolanaPublicKey(data: derivedPubData)

        guard derivedKey == keypair.publicKey else {
            throw SolanaError.publicKeyMismatch
        }
        self.publicKey = derivedKey
    }

    public func sign(message: Data) async throws -> Data {
        let signature = try privateKey.signature(for: message)
        return Data(signature)
    }

    /// Verify a signature against a message
    public static func verify(signature: Data, message: Data, publicKey: SolanaPublicKey) -> Bool {
        guard let pubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey.data) else {
            return false
        }
        return pubKey.isValidSignature(signature, for: message)
    }
}
