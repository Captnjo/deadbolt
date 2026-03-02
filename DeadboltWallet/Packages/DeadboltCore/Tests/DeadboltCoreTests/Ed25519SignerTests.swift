import XCTest
import CryptoKit
@testable import DeadboltCore

final class Ed25519SignerTests: XCTestCase {

    // MARK: - Sign + Verify round trip

    func testSignAndVerify() async throws {
        let seed = Data(repeating: 0xAB, count: 32)
        let signer = try SoftwareSigner(seed: seed)

        let message = Data("Hello Solana".utf8)
        let signature = try await signer.sign(message: message)

        XCTAssertEqual(signature.count, 64, "Ed25519 signature should be 64 bytes")

        let valid = SoftwareSigner.verify(signature: signature, message: message, publicKey: signer.publicKey)
        XCTAssertTrue(valid)
    }

    // MARK: - Wrong message fails verification

    func testVerifyWrongMessageFails() async throws {
        let seed = Data(repeating: 0xCD, count: 32)
        let signer = try SoftwareSigner(seed: seed)

        let message = Data("correct message".utf8)
        let wrongMessage = Data("wrong message".utf8)
        let signature = try await signer.sign(message: message)

        let valid = SoftwareSigner.verify(signature: signature, message: wrongMessage, publicKey: signer.publicKey)
        XCTAssertFalse(valid)
    }

    // MARK: - Public key derivation is deterministic

    func testDeterministicPublicKey() throws {
        let seed = Data(repeating: 0xEF, count: 32)
        let signer1 = try SoftwareSigner(seed: seed)
        let signer2 = try SoftwareSigner(seed: seed)
        XCTAssertEqual(signer1.publicKey, signer2.publicKey)
    }

    // MARK: - Keypair verification

    func testKeypairPublicKeyMismatchThrows() throws {
        let seed = Data(repeating: 0x11, count: 32)
        let wrongPubKey = try SolanaPublicKey(data: Data(repeating: 0x22, count: 32))
        let keypair = Keypair(seed: seed, publicKey: wrongPubKey)

        XCTAssertThrowsError(try SoftwareSigner(keypair: keypair)) { error in
            guard case SolanaError.publicKeyMismatch = error else {
                XCTFail("Expected publicKeyMismatch, got \(error)")
                return
            }
        }
    }

    // MARK: - Cross-check with CryptoKit directly

    func testCrossCheckWithCryptoKit() async throws {
        let seed = Data(repeating: 0x55, count: 32)
        let signer = try SoftwareSigner(seed: seed)

        // Same key via CryptoKit directly
        let ckKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        XCTAssertEqual(Data(ckKey.publicKey.rawRepresentation), signer.publicKey.data)

        let message = Data("test transaction bytes".utf8)
        let signature = try await signer.sign(message: message)

        // Verify with CryptoKit directly
        let valid = ckKey.publicKey.isValidSignature(signature, for: message)
        XCTAssertTrue(valid)
    }
}
