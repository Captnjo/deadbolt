import XCTest
import CryptoKit
@testable import DeadboltCore

/// P9-008: Performance tests for key operations.
/// Uses XCTest measure blocks to benchmark Ed25519 key generation, transaction building,
/// Base58 encode/decode, PDA derivation, and BIP39 mnemonic generation + seed derivation.
final class PerformanceTests: XCTestCase {

    // MARK: - Ed25519 Key Generation from Seed

    func testPerformance_Ed25519KeyGeneration() throws {
        let seed = Data(repeating: 0x42, count: 32)

        measure {
            for _ in 0..<100 {
                _ = try! SoftwareSigner(seed: seed)
            }
        }
    }

    // MARK: - Transaction Building (Message creation + serialization)

    func testPerformance_TransactionBuilding() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0xAA, count: 32))

        measure {
            for _ in 0..<100 {
                let message = try! Message(
                    feePayer: feePayer,
                    recentBlockhash: blockhash,
                    instructions: [
                        ComputeBudgetProgram.setComputeUnitLimit(200_000),
                        ComputeBudgetProgram.setComputeUnitPrice(50_000),
                        SystemProgram.transfer(from: feePayer, to: recipient, lamports: 1_000_000),
                    ]
                )
                let tx = Transaction(message: message)
                _ = tx.serialize()
            }
        }
    }

    // MARK: - Base58 Encode/Decode for Public Key

    func testPerformance_Base58EncodeDecode() throws {
        let pubKeyData = Data(repeating: 0x55, count: 32)

        measure {
            for _ in 0..<1000 {
                let encoded = Base58.encode(pubKeyData)
                _ = try! Base58.decode(encoded)
            }
        }
    }

    // MARK: - PDA Derivation

    func testPerformance_PDADerivation() throws {
        let programId = try SolanaPublicKey(base58: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
        let owner = Data(repeating: 0x01, count: 32)
        let mint = Data(repeating: 0x02, count: 32)

        measure {
            for _ in 0..<10 {
                _ = try! SolanaPublicKey.findProgramAddress(
                    seeds: [owner, programId.data, mint],
                    programId: try! SolanaPublicKey(base58: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")
                )
            }
        }
    }

    // MARK: - BIP39 Mnemonic Generation

    func testPerformance_MnemonicGeneration() {
        measure {
            for _ in 0..<100 {
                _ = try! Mnemonic.generate(wordCount: 12)
            }
        }
    }

    // MARK: - BIP39 Seed Derivation (PBKDF2)

    func testPerformance_BIP39SeedDerivation() throws {
        // This is intentionally slow (2048 rounds of PBKDF2-HMAC-SHA512)
        let words = try Mnemonic.generate(wordCount: 12)

        measure {
            _ = try! Mnemonic.toSeed(words: words)
        }
    }

    // MARK: - Ed25519 Sign Operation

    func testPerformance_Ed25519Signing() throws {
        let signer = try SoftwareSigner(seed: Data(repeating: 0x01, count: 32))
        let message = Data(repeating: 0xBB, count: 256)

        measure {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                for _ in 0..<100 {
                    _ = try await signer.sign(message: message)
                }
                semaphore.signal()
            }
            semaphore.wait()
        }
    }
}
