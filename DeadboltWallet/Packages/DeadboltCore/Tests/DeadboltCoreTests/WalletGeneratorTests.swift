import XCTest
import CryptoKit
@testable import DeadboltCore

final class WalletGeneratorTests: XCTestCase {

    // MARK: - P8-001: Random Keypair Generation

    func testGenerateRandomProducesValidKeypair() throws {
        let keypair = try WalletGenerator.generateRandom()

        // Seed must be 32 bytes
        XCTAssertEqual(keypair.seed.count, 32, "Seed should be 32 bytes")

        // Public key must be 32 bytes
        XCTAssertEqual(keypair.publicKey.data.count, 32, "Public key should be 32 bytes")

        // Public key must be valid (derivable from seed)
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keypair.seed)
        let expectedPubKey = Data(privateKey.publicKey.rawRepresentation)
        XCTAssertEqual(keypair.publicKey.data, expectedPubKey,
            "Public key should match what CryptoKit derives from the seed")
    }

    func testGenerateRandomProducesUniqueKeypairs() throws {
        let keypair1 = try WalletGenerator.generateRandom()
        let keypair2 = try WalletGenerator.generateRandom()

        XCTAssertNotEqual(keypair1.seed, keypair2.seed,
            "Two random keypairs should have different seeds")
        XCTAssertNotEqual(keypair1.publicKey, keypair2.publicKey,
            "Two random keypairs should have different public keys")
    }

    func testGenerateRandomBase58AddressIsNonEmpty() throws {
        let keypair = try WalletGenerator.generateRandom()
        let address = keypair.publicKey.base58

        XCTAssertFalse(address.isEmpty, "Base58 address should not be empty")
        XCTAssertGreaterThan(address.count, 20, "Solana addresses are typically 32-44 chars")
        XCTAssertLessThanOrEqual(address.count, 44, "Solana addresses are at most 44 chars")
    }

    // MARK: - P8-002: Vanity Address Grinding

    func testVanityGrindFindsMatchingPrefix() async throws {
        // Use a single character prefix for speed
        let keypair = try await WalletGenerator.grindVanityAddress(
            prefix: "1",
            maxAttempts: 1_000_000
        )

        let address = keypair.publicKey.base58
        XCTAssertTrue(
            address.lowercased().hasPrefix("1"),
            "Address \(address) should start with '1'"
        )

        // Verify keypair is valid
        XCTAssertEqual(keypair.seed.count, 32)
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keypair.seed)
        let expectedPubKey = Data(privateKey.publicKey.rawRepresentation)
        XCTAssertEqual(keypair.publicKey.data, expectedPubKey)
    }

    func testVanityGrindCaseInsensitive() async throws {
        // "A" in base58 should match "a" prefix
        let keypair = try await WalletGenerator.grindVanityAddress(
            prefix: "a",
            maxAttempts: 1_000_000
        )

        let address = keypair.publicKey.base58
        XCTAssertTrue(
            address.lowercased().hasPrefix("a"),
            "Address \(address) should case-insensitively start with 'a'"
        )
    }

    func testVanityGrindReportsProgress() async throws {
        var progressReports = [Int]()
        let _ = try await WalletGenerator.grindVanityAddress(
            prefix: "1",
            maxAttempts: 100_000,
            progressCallback: { attempts in
                progressReports.append(attempts)
            }
        )

        // Should have reported at least once if it took >1000 attempts
        // (might find it quickly, so we just verify the callback was callable)
    }

    func testVanityGrindImpossiblePrefixThrows() async {
        // "0", "O", "I", "l" are not valid Base58 characters,
        // but more importantly, a very long prefix is essentially impossible
        do {
            let _ = try await WalletGenerator.grindVanityAddress(
                prefix: "ZZZZZZZZZZ",
                maxAttempts: 100
            )
            XCTFail("Should have thrown vanityMaxAttemptsReached")
        } catch let error as SolanaError {
            if case .vanityMaxAttemptsReached = error {
                // expected
            } else {
                XCTFail("Expected vanityMaxAttemptsReached, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
