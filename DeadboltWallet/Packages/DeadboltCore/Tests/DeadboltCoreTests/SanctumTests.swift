import XCTest
@testable import DeadboltCore

final class SanctumTests: XCTestCase {

    // MARK: - SanctumQuote Decoding

    func testSanctumQuoteDecoding() throws {
        let json = """
        {
            "inAmount": "1000000000",
            "outAmount": "980000000",
            "feeAmount": "1000000",
            "feePct": "0.001"
        }
        """.data(using: .utf8)!

        let quote = try JSONDecoder().decode(SanctumQuote.self, from: json)

        XCTAssertEqual(quote.inAmount, "1000000000")
        XCTAssertEqual(quote.outAmount, "980000000")
        XCTAssertEqual(quote.feeAmount, "1000000")
        XCTAssertEqual(quote.feePct, "0.001")
    }

    func testSanctumQuoteRoundTrip() throws {
        let json = """
        {
            "inAmount": "500000000",
            "outAmount": "490500000",
            "feeAmount": "500000",
            "feePct": "0.001"
        }
        """.data(using: .utf8)!

        let quote = try JSONDecoder().decode(SanctumQuote.self, from: json)
        let encoded = try JSONEncoder().encode(quote)
        let roundTripped = try JSONDecoder().decode(SanctumQuote.self, from: encoded)

        XCTAssertEqual(roundTripped.inAmount, quote.inAmount)
        XCTAssertEqual(roundTripped.outAmount, quote.outAmount)
        XCTAssertEqual(roundTripped.feeAmount, quote.feeAmount)
        XCTAssertEqual(roundTripped.feePct, quote.feePct)
    }

    // MARK: - SanctumSwapResponse Decoding

    func testSanctumSwapResponseDecoding() throws {
        // Simulate a swap response with a mock base64 transaction
        let json = """
        {
            "tx": "AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SanctumSwapResponse.self, from: json)
        XCTAssertFalse(response.tx.isEmpty)

        // Verify it's valid base64
        let decoded = Data(base64Encoded: response.tx)
        XCTAssertNotNil(decoded)
    }

    // MARK: - SanctumPriceResponse Decoding

    func testSanctumPriceResponseDecoding() throws {
        let json = """
        {
            "amount": "980000000"
        }
        """.data(using: .utf8)!

        let price = try JSONDecoder().decode(SanctumPriceResponse.self, from: json)
        XCTAssertEqual(price.amount, "980000000")
    }

    func testSanctumPriceResponseRoundTrip() throws {
        let json = """
        {
            "amount": "1050000000"
        }
        """.data(using: .utf8)!

        let price = try JSONDecoder().decode(SanctumPriceResponse.self, from: json)
        let encoded = try JSONEncoder().encode(price)
        let roundTripped = try JSONDecoder().decode(SanctumPriceResponse.self, from: encoded)

        XCTAssertEqual(roundTripped.amount, price.amount)
    }

    // MARK: - SanctumSwapRequest Encoding

    func testSanctumSwapRequestEncoding() throws {
        let request = SanctumSwapRequest(
            input: LSTMint.wrappedSOL,
            outputLstMint: LSTMint.jitoSOL,
            amount: "1000000000",
            quotedAmount: "980000000",
            signer: "DummySignerPublicKey11111111111111111111111",
            mode: "ExactIn"
        )

        let encoded = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["input"] as? String, LSTMint.wrappedSOL)
        XCTAssertEqual(json?["outputLstMint"] as? String, LSTMint.jitoSOL)
        XCTAssertEqual(json?["amount"] as? String, "1000000000")
        XCTAssertEqual(json?["quotedAmount"] as? String, "980000000")
        XCTAssertEqual(json?["mode"] as? String, "ExactIn")
    }

    // MARK: - LSTMint Constants

    func testLSTMintConstants() {
        XCTAssertEqual(LSTMint.wrappedSOL, "So11111111111111111111111111111111111111112")
        XCTAssertEqual(LSTMint.jitoSOL, "J1toso1uCk3RLmjorhTtrVwY9HJ7X8V9yYac6Y7kGCPn")
        XCTAssertEqual(LSTMint.mSOL, "mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So")
        XCTAssertEqual(LSTMint.bSOL, "bSo13r4TkiE4KumL71LsHTPpL2euBYLFx6h9HP3piy1")
        XCTAssertEqual(LSTMint.bonkSOL, "BonK1YhkXEGLZzwtcvRTip3gAL9nCeQD7ppZBLXhtTs")
    }

    // MARK: - VersionedTransaction Deserialization (Legacy)

    func testLegacyTransactionDeserializeRoundTrip() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0xAA, count: 32))

        let transferIx = SystemProgram.transfer(from: feePayer, to: recipient, lamports: 100)
        let message = try Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: [transferIx]
        )

        let original = VersionedTransaction(message: .legacy(message))
        let serialized = original.serialize()

        // Deserialize
        let deserialized = try VersionedTransaction.deserialize(from: serialized)

        // Verify round-trip
        let reserialized = deserialized.serialize()
        XCTAssertEqual(serialized, reserialized, "Legacy transaction round-trip serialization must match")

        // Verify signature count
        XCTAssertEqual(deserialized.signatures.count, 1)
        XCTAssertEqual(deserialized.signatures[0], Data(repeating: 0, count: 64))

        // Verify message type
        if case .legacy(let msg) = deserialized.message {
            XCTAssertEqual(msg.header.numRequiredSignatures, 1)
            XCTAssertEqual(msg.accountKeys.count, 3) // feePayer, recipient, system program
            XCTAssertEqual(msg.accountKeys[0], feePayer)
            XCTAssertEqual(msg.instructions.count, 1)
        } else {
            XCTFail("Expected legacy message")
        }
    }

    // MARK: - VersionedTransaction Deserialization (V0)

    func testV0TransactionDeserializeRoundTrip() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0xBB, count: 32))

        let transferIx = SystemProgram.transfer(from: feePayer, to: recipient, lamports: 1_000_000)
        let v0Message = try V0Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: [transferIx],
            addressLookupTables: []
        )

        let original = VersionedTransaction(message: .v0(v0Message))
        let serialized = original.serialize()

        // Deserialize
        let deserialized = try VersionedTransaction.deserialize(from: serialized)

        // Verify round-trip
        let reserialized = deserialized.serialize()
        XCTAssertEqual(serialized, reserialized, "V0 transaction round-trip serialization must match")

        // Verify message type
        if case .v0(let msg) = deserialized.message {
            XCTAssertEqual(msg.header.numRequiredSignatures, 1)
            XCTAssertEqual(msg.accountKeys.count, 3)
            XCTAssertEqual(msg.accountKeys[0], feePayer)
            XCTAssertEqual(msg.recentBlockhash, Data(repeating: 0xBB, count: 32))
            XCTAssertEqual(msg.instructions.count, 1)
            XCTAssertEqual(msg.addressTableLookups.count, 0)
        } else {
            XCTFail("Expected v0 message")
        }
    }

    func testV0TransactionWithALTDeserializeRoundTrip() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let altKey = try SolanaPublicKey(data: Data(repeating: 0xAA, count: 32))
        let altAddress1 = try SolanaPublicKey(data: Data(repeating: 0xBB, count: 32))
        let altAddress2 = try SolanaPublicKey(data: Data(repeating: 0xCC, count: 32))

        let blockhash = Base58.encode(Data(repeating: 0x00, count: 32))

        let ix = Instruction(
            programId: SystemProgram.programId,
            accounts: [
                AccountMeta(publicKey: feePayer, isSigner: true, isWritable: true),
                AccountMeta(publicKey: altAddress1, isSigner: false, isWritable: true),
                AccountMeta(publicKey: altAddress2, isSigner: false, isWritable: false),
            ],
            data: Data([0x01])
        )

        let alt = AddressLookupTable(key: altKey, addresses: [altAddress1, altAddress2])

        let v0Message = try V0Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: [ix],
            addressLookupTables: [alt]
        )

        let original = VersionedTransaction(message: .v0(v0Message))
        let serialized = original.serialize()

        // Deserialize
        let deserialized = try VersionedTransaction.deserialize(from: serialized)

        // Verify round-trip
        let reserialized = deserialized.serialize()
        XCTAssertEqual(serialized, reserialized, "V0 transaction with ALTs round-trip must match")

        // Verify ALT lookups
        if case .v0(let msg) = deserialized.message {
            XCTAssertEqual(msg.addressTableLookups.count, 1)
            XCTAssertEqual(msg.addressTableLookups[0].accountKey, altKey)
            XCTAssertEqual(msg.addressTableLookups[0].writableIndexes, [0])
            XCTAssertEqual(msg.addressTableLookups[0].readonlyIndexes, [1])
            // Static keys: feePayer + System program only
            XCTAssertEqual(msg.accountKeys.count, 2)
        } else {
            XCTFail("Expected v0 message")
        }
    }

    func testSignedV0TransactionDeserializeRoundTrip() async throws {
        let signer = try SoftwareSigner(seed: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0xCC, count: 32))

        let transferIx = SystemProgram.transfer(from: signer.publicKey, to: recipient, lamports: 500_000)
        let v0Message = try V0Message(
            feePayer: signer.publicKey,
            recentBlockhash: blockhash,
            instructions: [transferIx],
            addressLookupTables: []
        )

        var original = VersionedTransaction(message: .v0(v0Message))
        try await original.sign(with: signer)

        let serialized = original.serialize()

        // Deserialize
        let deserialized = try VersionedTransaction.deserialize(from: serialized)

        // Verify round-trip
        let reserialized = deserialized.serialize()
        XCTAssertEqual(serialized, reserialized, "Signed V0 transaction round-trip must match")

        // Signature should not be all zeros
        XCTAssertNotEqual(deserialized.signatures[0], Data(repeating: 0, count: 64))

        // Verify the signature is preserved
        XCTAssertEqual(deserialized.signatures[0], original.signatures[0])
    }

    func testBase64TransactionDeserializeRoundTrip() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0x00, count: 32))

        let transferIx = SystemProgram.transfer(from: feePayer, to: recipient, lamports: 100)
        let v0Message = try V0Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: [transferIx],
            addressLookupTables: []
        )

        let original = VersionedTransaction(message: .v0(v0Message))
        let base64Str = original.serializeBase64()

        // Simulate receiving a base64 transaction (like from Sanctum API)
        guard let txData = Data(base64Encoded: base64Str) else {
            XCTFail("Failed to decode base64 string")
            return
        }

        let deserialized = try VersionedTransaction.deserialize(from: txData)
        let reserialized = deserialized.serializeBase64()

        XCTAssertEqual(base64Str, reserialized, "Base64 round-trip must match")
    }

    // MARK: - Deserialization Error Cases

    func testDeserializeEmptyData() {
        let emptyData = Data()
        XCTAssertThrowsError(try VersionedTransaction.deserialize(from: emptyData)) { error in
            if case SolanaError.decodingError = error {
                // Expected
            } else {
                XCTFail("Expected SolanaError.decodingError, got \(error)")
            }
        }
    }

    func testDeserializeTruncatedSignature() {
        // compact-u16(1) = [0x01], then only 10 bytes of signature (need 64)
        var data = Data()
        data.append(0x01) // 1 signature
        data.append(contentsOf: Data(repeating: 0x00, count: 10)) // truncated

        XCTAssertThrowsError(try VersionedTransaction.deserialize(from: data))
    }

    func testDeserializeTruncatedMessage() {
        // Valid signature section but truncated message
        var data = Data()
        data.append(0x01) // 1 signature
        data.append(contentsOf: Data(repeating: 0x00, count: 64)) // full signature
        // Only 1 byte of message (not enough for header)
        data.append(0x80) // v0 prefix but no header bytes

        XCTAssertThrowsError(try VersionedTransaction.deserialize(from: data))
    }

    // MARK: - V0Message Deserialization

    func testV0MessageDeserializeMultipleInstructions() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient1 = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let recipient2 = try SolanaPublicKey(data: Data(repeating: 0x03, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0xDD, count: 32))

        let ix1 = SystemProgram.transfer(from: feePayer, to: recipient1, lamports: 100)
        let ix2 = SystemProgram.transfer(from: feePayer, to: recipient2, lamports: 200)

        let v0Message = try V0Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: [ix1, ix2],
            addressLookupTables: []
        )

        let serialized = v0Message.serialize()

        // Deserialize (skip the 0x80 prefix)
        var offset = 1
        let deserialized = try V0Message(deserializing: serialized, offset: &offset)

        XCTAssertEqual(deserialized.header.numRequiredSignatures, v0Message.header.numRequiredSignatures)
        XCTAssertEqual(deserialized.accountKeys.count, v0Message.accountKeys.count)
        XCTAssertEqual(deserialized.recentBlockhash, v0Message.recentBlockhash)
        XCTAssertEqual(deserialized.instructions.count, 2)
        XCTAssertEqual(deserialized.addressTableLookups.count, 0)

        // Verify instruction data matches
        for i in 0..<deserialized.instructions.count {
            XCTAssertEqual(deserialized.instructions[i].programIdIndex, v0Message.instructions[i].programIdIndex)
            XCTAssertEqual(deserialized.instructions[i].accountIndices, v0Message.instructions[i].accountIndices)
            XCTAssertEqual(deserialized.instructions[i].data, v0Message.instructions[i].data)
        }
    }

    // MARK: - Legacy Message Deserialization

    func testLegacyMessageDeserializeRoundTrip() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0xEE, count: 32))

        let transferIx = SystemProgram.transfer(from: feePayer, to: recipient, lamports: 42)
        let message = try Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: [transferIx]
        )

        let serialized = message.serialize()

        // Deserialize
        var offset = 0
        let deserialized = try Message(deserializing: serialized, offset: &offset)

        XCTAssertEqual(deserialized.header.numRequiredSignatures, message.header.numRequiredSignatures)
        XCTAssertEqual(deserialized.header.numReadonlySignedAccounts, message.header.numReadonlySignedAccounts)
        XCTAssertEqual(deserialized.header.numReadonlyUnsignedAccounts, message.header.numReadonlyUnsignedAccounts)
        XCTAssertEqual(deserialized.accountKeys.count, message.accountKeys.count)
        XCTAssertEqual(deserialized.recentBlockhash, message.recentBlockhash)
        XCTAssertEqual(deserialized.instructions.count, message.instructions.count)

        // Verify the serialized form matches
        let reserialized = deserialized.serialize()
        XCTAssertEqual(serialized, reserialized)
    }

    // MARK: - CompactU16 Decode Round Trip

    func testCompactU16DecodeSmallValues() throws {
        for value: UInt16 in [0, 1, 42, 127] {
            let encoded = Data(CompactU16.encode(value))
            let (decoded, bytesRead) = try CompactU16.decode(encoded, offset: 0)
            XCTAssertEqual(decoded, value, "Value \(value) should round-trip")
            XCTAssertEqual(bytesRead, 1, "Values <= 127 should be 1 byte")
        }
    }

    func testCompactU16DecodeMediumValues() throws {
        for value: UInt16 in [128, 256, 1000, 16383] {
            let encoded = Data(CompactU16.encode(value))
            let (decoded, bytesRead) = try CompactU16.decode(encoded, offset: 0)
            XCTAssertEqual(decoded, value, "Value \(value) should round-trip")
            XCTAssertEqual(bytesRead, 2, "Values 128-16383 should be 2 bytes")
        }
    }

    func testCompactU16DecodeLargeValues() throws {
        for value: UInt16 in [16384, 32768, 65535] {
            let encoded = Data(CompactU16.encode(value))
            let (decoded, bytesRead) = try CompactU16.decode(encoded, offset: 0)
            XCTAssertEqual(decoded, value, "Value \(value) should round-trip")
            XCTAssertEqual(bytesRead, 3, "Values >= 16384 should be 3 bytes")
        }
    }
}
