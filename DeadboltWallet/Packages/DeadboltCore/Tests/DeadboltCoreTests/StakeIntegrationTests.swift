import XCTest
@testable import DeadboltCore

/// P5-012: Staking integration tests.
/// Since Sanctum doesn't support devnet, these test the transaction building logic
/// with mocked data: SanctumQuote parsing, base64 transaction deserialization,
/// and the deserialize-resign-serialize round-trip.
final class StakeIntegrationTests: XCTestCase {

    // MARK: - Test 1: SanctumQuote JSON parsing with realistic mock data

    func testSanctumQuoteParsingRealisticMockData() throws {
        // Realistic Sanctum API response for 1 SOL -> JitoSOL
        let json = """
        {
            "inAmount": "1000000000",
            "outAmount": "942507823",
            "feeAmount": "500000",
            "feePct": "0.0005"
        }
        """.data(using: .utf8)!

        let quote = try JSONDecoder().decode(SanctumQuote.self, from: json)

        XCTAssertEqual(quote.inAmount, "1000000000")
        XCTAssertEqual(quote.outAmount, "942507823")
        XCTAssertEqual(quote.feeAmount, "500000")
        XCTAssertEqual(quote.feePct, "0.0005")

        // Verify the amounts make sense: outAmount < inAmount (fee was taken)
        let inAmount = UInt64(quote.inAmount)!
        let outAmount = UInt64(quote.outAmount)!
        let feeAmount = UInt64(quote.feeAmount)!
        XCTAssertTrue(outAmount < inAmount, "Output should be less than input due to fees")
        XCTAssertTrue(feeAmount > 0, "Fee should be positive")

        // Verify fee percentage is reasonable (< 1%)
        let feePct = Double(quote.feePct)!
        XCTAssertTrue(feePct < 0.01, "Fee percentage should be less than 1%")
        XCTAssertTrue(feePct > 0, "Fee percentage should be positive")
    }

    // MARK: - Test 2: VersionedTransaction deserialization from base64 (simulating Sanctum response)

    func testVersionedTransactionDeserializationFromBase64() throws {
        // Build a realistic V0 transaction that simulates what Sanctum returns
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let sanctumProgram = try SolanaPublicKey(data: Data(repeating: 0x08, count: 32))
        let lstMint = try SolanaPublicKey(data: Data(repeating: 0x09, count: 32))

        let instructions: [Instruction] = [
            ComputeBudgetProgram.setComputeUnitLimit(400_000),
            ComputeBudgetProgram.setComputeUnitPrice(100_000),
            // Simulated Sanctum stake instruction
            Instruction(
                programId: sanctumProgram,
                accounts: [
                    AccountMeta(publicKey: feePayer, isSigner: true, isWritable: true),
                    AccountMeta(publicKey: lstMint, isSigner: false, isWritable: false),
                ],
                data: Data([0x01, 0x00, 0xCA, 0x9A, 0x3B, 0x00, 0x00, 0x00, 0x00]) // stake 1 SOL
            ),
        ]

        let blockhash = Base58.encode(Data(repeating: 0xAA, count: 32))

        let v0Message = try V0Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: instructions,
            addressLookupTables: []
        )

        let original = VersionedTransaction(message: .v0(v0Message))
        let base64Str = original.serializeBase64()

        // Simulate receiving base64 from Sanctum API (like SanctumSwapResponse.tx)
        XCTAssertFalse(base64Str.isEmpty, "Base64 string should not be empty")

        guard let txData = Data(base64Encoded: base64Str) else {
            XCTFail("Failed to decode base64 transaction string")
            return
        }

        let deserialized = try VersionedTransaction.deserialize(from: txData)

        // Verify message is v0
        if case .v0(let msg) = deserialized.message {
            XCTAssertEqual(msg.instructions.count, 3, "Should have 3 instructions (2 compute budget + 1 stake)")
            XCTAssertEqual(msg.accountKeys[0], feePayer, "Fee payer should be first account key")
            XCTAssertEqual(msg.addressTableLookups.count, 0)
        } else {
            XCTFail("Expected v0 message from deserialized Sanctum transaction")
        }

        // Verify signature is empty (unsigned from API)
        XCTAssertEqual(deserialized.signatures.count, 1, "Should have 1 signature slot")
        XCTAssertEqual(deserialized.signatures[0], Data(repeating: 0, count: 64),
                       "Signature should be empty (unsigned)")
    }

    // MARK: - Test 3: Deserialize -> re-sign -> serialize round-trip

    func testDeserializeResignSerializeRoundTrip() async throws {
        let signer = try SoftwareSigner(seed: Data(repeating: 0x01, count: 32))
        let lstMint = try SolanaPublicKey(data: Data(repeating: 0x09, count: 32))
        let sanctumProgram = try SolanaPublicKey(data: Data(repeating: 0x08, count: 32))

        let blockhash = Base58.encode(Data(repeating: 0xBB, count: 32))

        let instructions: [Instruction] = [
            ComputeBudgetProgram.setComputeUnitLimit(300_000),
            ComputeBudgetProgram.setComputeUnitPrice(50_000),
            Instruction(
                programId: sanctumProgram,
                accounts: [
                    AccountMeta(publicKey: signer.publicKey, isSigner: true, isWritable: true),
                    AccountMeta(publicKey: lstMint, isSigner: false, isWritable: false),
                ],
                data: Data([0x01, 0x80, 0x96, 0x98, 0x00, 0x00, 0x00, 0x00, 0x00]) // stake 0.1 SOL
            ),
        ]

        let v0Message = try V0Message(
            feePayer: signer.publicKey,
            recentBlockhash: blockhash,
            instructions: instructions,
            addressLookupTables: []
        )

        // Create unsigned transaction (as Sanctum API would return)
        let unsigned = VersionedTransaction(message: .v0(v0Message))
        let unsignedBase64 = unsigned.serializeBase64()

        // Step 1: Deserialize (simulating receiving from API)
        guard let txData = Data(base64Encoded: unsignedBase64) else {
            XCTFail("Failed to decode base64")
            return
        }
        var deserialized = try VersionedTransaction.deserialize(from: txData)

        // Verify initially unsigned
        XCTAssertEqual(deserialized.signatures[0], Data(repeating: 0, count: 64),
                       "Should be unsigned initially")

        // Step 2: Re-sign with our signer
        try await deserialized.sign(with: signer)

        // Verify now signed
        XCTAssertNotEqual(deserialized.signatures[0], Data(repeating: 0, count: 64),
                          "Should be signed after re-signing")

        // Step 3: Serialize back to base64 for submission
        let signedBase64 = deserialized.serializeBase64()
        XCTAssertNotEqual(signedBase64, unsignedBase64,
                          "Signed base64 should differ from unsigned")

        // Step 4: Verify the signed transaction is valid
        guard let finalData = Data(base64Encoded: signedBase64) else {
            XCTFail("Failed to decode signed base64")
            return
        }
        let finalTx = try VersionedTransaction.deserialize(from: finalData)

        // Message bytes must match (signing only changes the signature, not the message)
        XCTAssertEqual(unsigned.message.serialize(), finalTx.message.serialize(),
                       "Message bytes must be identical after re-signing")

        // Verify Ed25519 signature
        let messageBytes = finalTx.message.serialize()
        let isValid = SoftwareSigner.verify(
            signature: finalTx.signatures[0],
            message: messageBytes,
            publicKey: signer.publicKey
        )
        XCTAssertTrue(isValid, "Re-signed signature must be valid Ed25519")
    }

    // MARK: - Test 4: SanctumSwapResponse and SanctumSwapRequest encoding round-trip

    func testSanctumTypesRoundTrip() throws {
        // Test SanctumSwapRequest encoding
        let request = SanctumSwapRequest(
            input: LSTMint.wrappedSOL,
            outputLstMint: LSTMint.jitoSOL,
            amount: "2000000000",
            quotedAmount: "1885015646",
            signer: "HXkmkk76RKdPGEwCHfNMd7K1RPX6VX5GVR6pX3qxVcrX",
            mode: "ExactIn"
        )

        let encoded = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["input"] as? String, LSTMint.wrappedSOL)
        XCTAssertEqual(json?["outputLstMint"] as? String, LSTMint.jitoSOL)
        XCTAssertEqual(json?["amount"] as? String, "2000000000")
        XCTAssertEqual(json?["quotedAmount"] as? String, "1885015646")
        XCTAssertEqual(json?["mode"] as? String, "ExactIn")

        // Test SanctumSwapResponse decoding with mock base64 transaction
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0xCC, count: 32))
        let v0 = try V0Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: [ComputeBudgetProgram.setComputeUnitLimit(200_000)],
            addressLookupTables: []
        )
        let mockTx = VersionedTransaction(message: .v0(v0))
        let mockBase64 = mockTx.serializeBase64()

        let responseJson = """
        {
            "tx": "\(mockBase64)"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SanctumSwapResponse.self, from: responseJson)
        XCTAssertFalse(response.tx.isEmpty)

        // Verify the response transaction is deserializable
        let responseData = Data(base64Encoded: response.tx)
        XCTAssertNotNil(responseData)
        let deserializedTx = try VersionedTransaction.deserialize(from: responseData!)
        if case .v0 = deserializedTx.message {
            // Expected
        } else {
            XCTFail("Expected v0 message in swap response transaction")
        }
    }
}
