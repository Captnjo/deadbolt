import XCTest
import CryptoKit
@testable import DeadboltCore

/// P4-014: Swap transaction byte-compatibility tests.
/// Tests V0 versioned transactions with Jupiter-style instructions (compute budget +
/// token transfer + swap placeholder), verifying serialization round-trips correctly.
final class SwapCompatTests: XCTestCase {

    // Deterministic test keys
    private let feePayerSeed = Data(repeating: 0x01, count: 32)
    private let blockhash = "CVDFLCAjXhVWiPXH9nTCTpCgVzmDVoiPzNJYuccr1dqB"

    // MARK: - Helpers

    private func createTestSigner() throws -> SoftwareSigner {
        try SoftwareSigner(seed: feePayerSeed)
    }

    // MARK: - Test 1: V0 message with multiple Jupiter-style instructions round-trips

    func testV0MessageWithJupiterStyleInstructionsRoundTrip() throws {
        let signer = try createTestSigner()
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let tokenProgram = try SolanaPublicKey(data: Data(repeating: 0x06, count: 32))

        // Build Jupiter-style instructions: compute budget + token transfer + swap placeholder
        let computeLimitIx = ComputeBudgetProgram.setComputeUnitLimit(400_000)
        let computePriceIx = ComputeBudgetProgram.setComputeUnitPrice(100_000)

        // Simulate a token transfer instruction (like Jupiter internal routing)
        let tokenTransferIx = Instruction(
            programId: tokenProgram,
            accounts: [
                AccountMeta(publicKey: signer.publicKey, isSigner: true, isWritable: true),
                AccountMeta(publicKey: recipient, isSigner: false, isWritable: true),
            ],
            data: Data([0x03, 0x40, 0x42, 0x0F, 0x00, 0x00, 0x00, 0x00, 0x00]) // transfer 1M
        )

        // Simulate a swap instruction placeholder
        let swapProgram = try SolanaPublicKey(data: Data(repeating: 0x07, count: 32))
        let swapIx = Instruction(
            programId: swapProgram,
            accounts: [
                AccountMeta(publicKey: signer.publicKey, isSigner: true, isWritable: true),
                AccountMeta(publicKey: recipient, isSigner: false, isWritable: true),
            ],
            data: Data([0xE5, 0x17, 0xCB, 0x97, 0x7A, 0xE3, 0xAD, 0x2A]) // Jupiter route discriminator
        )

        let v0Message = try V0Message(
            feePayer: signer.publicKey,
            recentBlockhash: blockhash,
            instructions: [computeLimitIx, computePriceIx, tokenTransferIx, swapIx],
            addressLookupTables: []
        )

        // Serialize
        let serialized = v0Message.serialize()

        // The first byte must be 0x80 (v0 prefix)
        XCTAssertEqual(serialized[0], 0x80, "V0 message must start with 0x80 prefix")

        // Deserialize (skip the 0x80 prefix)
        var offset = 1
        let deserialized = try V0Message(deserializing: serialized, offset: &offset)

        // Verify header
        XCTAssertEqual(deserialized.header.numRequiredSignatures, v0Message.header.numRequiredSignatures)
        XCTAssertEqual(deserialized.header.numReadonlySignedAccounts, v0Message.header.numReadonlySignedAccounts)
        XCTAssertEqual(deserialized.header.numReadonlyUnsignedAccounts, v0Message.header.numReadonlyUnsignedAccounts)

        // Verify account keys match count and content
        XCTAssertEqual(deserialized.accountKeys.count, v0Message.accountKeys.count)
        for i in 0..<deserialized.accountKeys.count {
            XCTAssertEqual(deserialized.accountKeys[i], v0Message.accountKeys[i],
                           "Account key \(i) mismatch")
        }

        // Verify 4 instructions round-tripped
        XCTAssertEqual(deserialized.instructions.count, 4)
        for i in 0..<deserialized.instructions.count {
            XCTAssertEqual(deserialized.instructions[i].programIdIndex, v0Message.instructions[i].programIdIndex)
            XCTAssertEqual(deserialized.instructions[i].accountIndices, v0Message.instructions[i].accountIndices)
            XCTAssertEqual(deserialized.instructions[i].data, v0Message.instructions[i].data)
        }

        // Verify byte-level round-trip
        let reserialized = deserialized.serialize()
        // Must skip the 0x80 prefix on the original for comparison, since V0Message.serialize() includes it
        XCTAssertEqual(serialized, reserialized, "V0 message serialize/deserialize round-trip must produce identical bytes")
    }

    // MARK: - Test 2: Signed V0 transaction with Jupiter-style instructions

    func testSignedV0TransactionWithSwapInstructions() async throws {
        let signer = try createTestSigner()
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let swapProgram = try SolanaPublicKey(data: Data(repeating: 0x07, count: 32))

        let instructions = [
            ComputeBudgetProgram.setComputeUnitLimit(300_000),
            ComputeBudgetProgram.setComputeUnitPrice(75_000),
            SystemProgram.transfer(from: signer.publicKey, to: recipient, lamports: 500_000),
            Instruction(
                programId: swapProgram,
                accounts: [
                    AccountMeta(publicKey: signer.publicKey, isSigner: true, isWritable: true),
                    AccountMeta(publicKey: recipient, isSigner: false, isWritable: true),
                ],
                data: Data([0xE5, 0x17, 0xCB, 0x97, 0x7A, 0xE3, 0xAD, 0x2A])
            ),
        ]

        let v0Message = try V0Message(
            feePayer: signer.publicKey,
            recentBlockhash: blockhash,
            instructions: instructions,
            addressLookupTables: []
        )

        var tx = VersionedTransaction(message: .v0(v0Message))
        try await tx.sign(with: signer)

        // Serialize
        let serialized = tx.serialize()

        // Deserialize
        let deserialized = try VersionedTransaction.deserialize(from: serialized)

        // Verify byte-level round-trip
        XCTAssertEqual(serialized, deserialized.serialize(),
                       "Signed V0 transaction round-trip must produce identical bytes")

        // Verify the signature is non-zero (was actually signed)
        XCTAssertNotEqual(deserialized.signatures[0], Data(repeating: 0, count: 64),
                          "Signature should not be all zeros after signing")

        // Verify the signature is valid Ed25519
        let messageBytes = tx.message.serialize()
        let isValid = SoftwareSigner.verify(
            signature: deserialized.signatures[0],
            message: messageBytes,
            publicKey: signer.publicKey
        )
        XCTAssertTrue(isValid, "Signature must be valid Ed25519 over the message bytes")

        // Verify message structure
        if case .v0(let msg) = deserialized.message {
            XCTAssertEqual(msg.instructions.count, 4, "Should have 4 instructions")
            XCTAssertEqual(msg.addressTableLookups.count, 0, "Should have no ALT lookups")
        } else {
            XCTFail("Expected v0 message")
        }
    }

    // MARK: - Test 3: V0 transaction with address lookup table references

    func testV0TransactionWithAddressLookupTableRoundTrip() async throws {
        let signer = try createTestSigner()
        let altKey = try SolanaPublicKey(data: Data(repeating: 0xAA, count: 32))
        let altAddr1 = try SolanaPublicKey(data: Data(repeating: 0xBB, count: 32))
        let altAddr2 = try SolanaPublicKey(data: Data(repeating: 0xCC, count: 32))
        let altAddr3 = try SolanaPublicKey(data: Data(repeating: 0xDD, count: 32))
        let swapProgram = try SolanaPublicKey(data: Data(repeating: 0x07, count: 32))

        // Build instructions that reference ALT addresses
        let instructions: [Instruction] = [
            ComputeBudgetProgram.setComputeUnitLimit(400_000),
            ComputeBudgetProgram.setComputeUnitPrice(50_000),
            // Swap instruction referencing ALT addresses as non-signer accounts
            Instruction(
                programId: swapProgram,
                accounts: [
                    AccountMeta(publicKey: signer.publicKey, isSigner: true, isWritable: true),
                    AccountMeta(publicKey: altAddr1, isSigner: false, isWritable: true),
                    AccountMeta(publicKey: altAddr2, isSigner: false, isWritable: true),
                    AccountMeta(publicKey: altAddr3, isSigner: false, isWritable: false),
                ],
                data: Data([0xE5, 0x17, 0xCB, 0x97])
            ),
        ]

        let alt = AddressLookupTable(key: altKey, addresses: [altAddr1, altAddr2, altAddr3])

        let v0Message = try V0Message(
            feePayer: signer.publicKey,
            recentBlockhash: blockhash,
            instructions: instructions,
            addressLookupTables: [alt]
        )

        // ALT addresses should NOT be in static keys
        let staticKeySet = Set(v0Message.accountKeys.map { $0.data })
        XCTAssertFalse(staticKeySet.contains(altAddr1.data), "ALT addr1 should not be in static keys")
        XCTAssertFalse(staticKeySet.contains(altAddr2.data), "ALT addr2 should not be in static keys")
        XCTAssertFalse(staticKeySet.contains(altAddr3.data), "ALT addr3 should not be in static keys")

        // Verify ALT lookups were created
        XCTAssertEqual(v0Message.addressTableLookups.count, 1, "Should have 1 ALT lookup entry")
        XCTAssertEqual(v0Message.addressTableLookups[0].accountKey, altKey)
        XCTAssertEqual(v0Message.addressTableLookups[0].writableIndexes.count, 2, "Two writable ALT addresses")
        XCTAssertEqual(v0Message.addressTableLookups[0].readonlyIndexes.count, 1, "One readonly ALT address")

        // Sign and serialize
        var tx = VersionedTransaction(message: .v0(v0Message))
        try await tx.sign(with: signer)
        let serialized = tx.serialize()

        // Deserialize
        let deserialized = try VersionedTransaction.deserialize(from: serialized)
        let reserialized = deserialized.serialize()

        // Full byte-level round-trip
        XCTAssertEqual(serialized, reserialized,
                       "V0 transaction with ALTs must round-trip exactly")

        // Verify ALT lookups survived round-trip
        if case .v0(let msg) = deserialized.message {
            XCTAssertEqual(msg.addressTableLookups.count, 1)
            XCTAssertEqual(msg.addressTableLookups[0].accountKey, altKey)
            XCTAssertEqual(msg.addressTableLookups[0].writableIndexes.count, 2)
            XCTAssertEqual(msg.addressTableLookups[0].readonlyIndexes.count, 1)
            XCTAssertEqual(msg.instructions.count, 3, "Should have 3 instructions")
        } else {
            XCTFail("Expected v0 message after deserialization")
        }

        // Verify signature validity
        let isValid = SoftwareSigner.verify(
            signature: deserialized.signatures[0],
            message: tx.message.serialize(),
            publicKey: signer.publicKey
        )
        XCTAssertTrue(isValid, "Signature must be valid Ed25519 after ALT round-trip")
    }

    // MARK: - Test 4: V0 transaction base64 round-trip (Jupiter API response simulation)

    func testV0TransactionBase64RoundTrip() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let swapProgram = try SolanaPublicKey(data: Data(repeating: 0x07, count: 32))

        let instructions = [
            ComputeBudgetProgram.setComputeUnitLimit(200_000),
            ComputeBudgetProgram.setComputeUnitPrice(50_000),
            SystemProgram.transfer(from: feePayer, to: recipient, lamports: 1_000_000),
            Instruction(
                programId: swapProgram,
                accounts: [
                    AccountMeta(publicKey: feePayer, isSigner: true, isWritable: true),
                    AccountMeta(publicKey: recipient, isSigner: false, isWritable: true),
                ],
                data: Data([0xE5, 0x17, 0xCB, 0x97, 0x7A, 0xE3, 0xAD, 0x2A])
            ),
        ]

        let v0Message = try V0Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: instructions,
            addressLookupTables: []
        )

        let original = VersionedTransaction(message: .v0(v0Message))
        let base64Str = original.serializeBase64()

        // Simulate receiving base64 from Jupiter API
        guard let txData = Data(base64Encoded: base64Str) else {
            XCTFail("Failed to decode base64")
            return
        }

        let deserialized = try VersionedTransaction.deserialize(from: txData)
        let reBase64 = deserialized.serializeBase64()

        XCTAssertEqual(base64Str, reBase64, "Base64 round-trip must match exactly")

        // Verify v0 message structure preserved
        if case .v0(let msg) = deserialized.message {
            XCTAssertEqual(msg.instructions.count, 4)
            XCTAssertEqual(msg.accountKeys[0], feePayer)
        } else {
            XCTFail("Expected v0 message after base64 round-trip")
        }
    }
}
