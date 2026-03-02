import Foundation
import CryptoKit
import Security

public enum WalletGenerator {

    // MARK: - P8-001: Random keypair generation

    /// Generate a random Ed25519 keypair using SecRandomCopyBytes and store it in the Keychain.
    public static func generateRandom() throws -> Keypair {
        var seed = Data(count: 32)
        let status = seed.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw SolanaError.keychainError(status)
        }

        let secureSeed = SecureBytes(bytes: seed)
        seed.zeroOut()

        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: secureSeed.data)
        let pubKeyData = Data(privateKey.publicKey.rawRepresentation)
        let publicKey = try SolanaPublicKey(data: pubKeyData)

        let keypair = Keypair(seed: secureSeed.data, publicKey: publicKey)

        // Store in Keychain
        try KeychainManager.storeSeed(secureSeed.data, address: publicKey.base58)

        return keypair
    }

    // MARK: - P8-002: Vanity address grinding

    /// Grind for a vanity address whose base58 representation starts with the given prefix (case-insensitive).
    /// - Parameters:
    ///   - prefix: The desired base58 prefix to match (case-insensitive).
    ///   - maxAttempts: Maximum number of attempts before giving up. Defaults to 1,000,000.
    ///   - progressCallback: Optional callback reporting the number of attempts so far (called every 1000 attempts).
    /// - Returns: A Keypair whose public key base58 address starts with the prefix.
    /// - Throws: `SolanaError.vanityMaxAttemptsReached` if no match is found within maxAttempts.
    public static func grindVanityAddress(
        prefix: String,
        maxAttempts: Int = 1_000_000,
        progressCallback: ((Int) -> Void)? = nil
    ) async throws -> Keypair {
        let lowercasedPrefix = prefix.lowercased()

        for attempt in 1...maxAttempts {
            var seed = Data(count: 32)
            let status = seed.withUnsafeMutableBytes { buffer in
                SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
            }
            guard status == errSecSuccess else {
                throw SolanaError.keychainError(status)
            }

            let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
            let pubKeyData = Data(privateKey.publicKey.rawRepresentation)
            let address = Base58.encode(pubKeyData)

            if address.lowercased().hasPrefix(lowercasedPrefix) {
                let secureSeed = SecureBytes(bytes: seed)
                seed.zeroOut()
                let publicKey = try SolanaPublicKey(data: pubKeyData)
                let keypair = Keypair(seed: secureSeed.data, publicKey: publicKey)

                // Store in Keychain
                try KeychainManager.storeSeed(secureSeed.data, address: publicKey.base58)

                return keypair
            }

            // Zero rejected seed immediately
            seed.zeroOut()

            if attempt % 1000 == 0 {
                progressCallback?(attempt)
            }
        }

        throw SolanaError.vanityMaxAttemptsReached
    }
}
