import XCTest
import CryptoKit
@testable import DeadboltCore

final class VersionedMessageTests: XCTestCase {

    // MARK: - Helpers

    private func dataToHex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - V0Message Serialization

    func testV0MessagePrefixByte() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0xAA, count: 32))

        let transferIx = SystemProgram.transfer(from: feePayer, to: recipient, lamports: 100)

        let v0Message = try V0Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: [transferIx],
            addressLookupTables: []
        )

        let serialized = v0Message.serialize()

        // First byte must be 0x80 (v0 prefix)
        XCTAssertEqual(serialized[0], 0x80, "V0 message must start with 0x80 prefix byte")
    }

    func testV0MessageWithoutALTs() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhashBytes = Data(repeating: 0xAA, count: 32)
        let blockhash = Base58.encode(blockhashBytes)

        let transferIx = SystemProgram.transfer(from: feePayer, to: recipient, lamports: 100)

        let v0Message = try V0Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: [transferIx],
            addressLookupTables: []
        )

        let serialized = v0Message.serialize()

        // Byte 0: v0 prefix (0x80)
        XCTAssertEqual(serialized[0], 0x80)

        // Bytes 1-3: header
        XCTAssertEqual(serialized[1], 1) // numRequiredSignatures
        XCTAssertEqual(serialized[2], 0) // numReadonlySignedAccounts
        XCTAssertEqual(serialized[3], 1) // numReadonlyUnsignedAccounts (System program)

        // Byte 4: compact-u16 account count = 3
        XCTAssertEqual(serialized[4], 3)

        // Bytes 5-36: fee payer
        XCTAssertEqual(Data(serialized[5..<37]), Data(repeating: 0x01, count: 32))

        // Bytes 37-68: recipient
        XCTAssertEqual(Data(serialized[37..<69]), Data(repeating: 0x02, count: 32))

        // Bytes 69-100: System program
        XCTAssertEqual(Data(serialized[69..<101]), SystemProgram.programId.data)

        // Bytes 101-132: blockhash
        XCTAssertEqual(Data(serialized[101..<133]), blockhashBytes)

        // Byte 133: compact-u16 instruction count = 1
        XCTAssertEqual(serialized[133], 1)

        // The instruction section follows (same as legacy)
        // Byte 134: programIdIndex = 2
        XCTAssertEqual(serialized[134], 2)

        // After instructions: ALT count = 0
        // Find the end of the instruction section
        // instruction: programIdIndex(1) + compact(accountIndices.count)(1) + indices(2) + compact(data.count)(1) + data(12)
        let endOfInstructions = 134 + 1 + 1 + 2 + 1 + 12
        XCTAssertEqual(serialized[endOfInstructions], 0, "ALT count should be 0")
    }

    func testV0MessageWithAddressLookupTables() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let altKey = try SolanaPublicKey(data: Data(repeating: 0xAA, count: 32))
        let altAddress1 = try SolanaPublicKey(data: Data(repeating: 0xBB, count: 32))
        let altAddress2 = try SolanaPublicKey(data: Data(repeating: 0xCC, count: 32))

        let blockhash = Base58.encode(Data(repeating: 0x00, count: 32))

        // Create an instruction that uses the ALT addresses as writable non-signer
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

        let serialized = v0Message.serialize()

        // First byte is v0 prefix
        XCTAssertEqual(serialized[0], 0x80)

        // Header: 1 signer, 0 readonly signed, 1 readonly unsigned (System program)
        XCTAssertEqual(serialized[1], 1) // numRequiredSignatures
        XCTAssertEqual(serialized[2], 0) // numReadonlySignedAccounts
        // System program is the only static non-signer readonly
        XCTAssertEqual(serialized[3], 1) // numReadonlyUnsignedAccounts

        // Static account keys should only contain feePayer and System program
        // (altAddress1 and altAddress2 are resolved via ALT)
        XCTAssertEqual(v0Message.accountKeys.count, 2, "Only feePayer and System program should be static keys")
        XCTAssertEqual(v0Message.accountKeys[0], feePayer)
        XCTAssertEqual(v0Message.accountKeys[1], SystemProgram.programId)

        // Should have 1 address table lookup
        XCTAssertEqual(v0Message.addressTableLookups.count, 1)
        XCTAssertEqual(v0Message.addressTableLookups[0].accountKey, altKey)
        XCTAssertEqual(v0Message.addressTableLookups[0].writableIndexes, [0]) // altAddress1 at index 0 in ALT
        XCTAssertEqual(v0Message.addressTableLookups[0].readonlyIndexes, [1]) // altAddress2 at index 1 in ALT
    }

    // MARK: - VersionedTransaction Serialization

    func testVersionedTransactionLegacySerialization() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0xAA, count: 32))

        let transferIx = SystemProgram.transfer(from: feePayer, to: recipient, lamports: 100)
        let message = try Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: [transferIx]
        )

        let tx = VersionedTransaction(message: .legacy(message))
        let serialized = tx.serialize()

        // Should be: compact-u16(1) + 64 bytes sig + message bytes
        XCTAssertEqual(serialized[0], 1) // 1 signature
        XCTAssertEqual(Data(serialized[1..<65]), Data(repeating: 0, count: 64)) // empty sig

        // Message should NOT start with 0x80
        XCTAssertEqual(serialized[65], 1) // numRequiredSignatures from header
    }

    func testVersionedTransactionV0Serialization() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0xAA, count: 32))

        let transferIx = SystemProgram.transfer(from: feePayer, to: recipient, lamports: 100)
        let v0Message = try V0Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: [transferIx],
            addressLookupTables: []
        )

        let tx = VersionedTransaction(message: .v0(v0Message))
        let serialized = tx.serialize()

        // Should be: compact-u16(1) + 64 bytes sig + v0 message bytes
        XCTAssertEqual(serialized[0], 1) // 1 signature
        XCTAssertEqual(Data(serialized[1..<65]), Data(repeating: 0, count: 64)) // empty sig

        // V0 message starts with 0x80
        XCTAssertEqual(serialized[65], 0x80, "V0 message in versioned transaction should start with 0x80")
    }

    func testVersionedTransactionSignAndVerify() async throws {
        let signer = try SoftwareSigner(seed: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0xAA, count: 32))

        let transferIx = SystemProgram.transfer(from: signer.publicKey, to: recipient, lamports: 1_000_000)
        let v0Message = try V0Message(
            feePayer: signer.publicKey,
            recentBlockhash: blockhash,
            instructions: [transferIx],
            addressLookupTables: []
        )

        var tx = VersionedTransaction(message: .v0(v0Message))
        try await tx.sign(with: signer)

        let serialized = tx.serialize()

        // Extract signature and message
        let signatureBytes = Data(serialized[1..<65])
        let messageBytes = Data(serialized[65...])

        // Signature should not be all zeros anymore
        XCTAssertNotEqual(signatureBytes, Data(repeating: 0, count: 64))

        // Verify Ed25519 signature
        let isValid = SoftwareSigner.verify(
            signature: signatureBytes,
            message: messageBytes,
            publicKey: signer.publicKey
        )
        XCTAssertTrue(isValid, "Signature must be valid Ed25519 over the v0 message bytes")
    }

    func testVersionedTransactionBase64() throws {
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

        let tx = VersionedTransaction(message: .v0(v0Message))
        let base64 = tx.serializeBase64()

        // Verify it round-trips through base64
        let decoded = Data(base64Encoded: base64)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded, tx.serialize())
    }

    // MARK: - VersionedMessage Enum

    func testVersionedMessageLegacySerialize() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0x00, count: 32))

        let transferIx = SystemProgram.transfer(from: feePayer, to: recipient, lamports: 100)
        let message = try Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: [transferIx]
        )

        let versioned = VersionedMessage.legacy(message)
        let serialized = versioned.serialize()

        // Legacy messages do not have a 0x80 prefix
        XCTAssertEqual(serialized[0], 1) // numRequiredSignatures
        XCTAssertEqual(serialized, message.serialize())
    }

    func testVersionedMessageV0Serialize() throws {
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

        let versioned = VersionedMessage.v0(v0Message)
        let serialized = versioned.serialize()

        // V0 messages start with 0x80 prefix
        XCTAssertEqual(serialized[0], 0x80)
        XCTAssertEqual(serialized, v0Message.serialize())
    }

    // MARK: - Address Lookup Table Deserialization

    func testAddressLookupTableDeserialize() throws {
        let altKey = try SolanaPublicKey(data: Data(repeating: 0xFF, count: 32))

        // Build a minimal ALT account data:
        // 56 bytes header + N * 32 bytes for addresses
        var altData = Data(repeating: 0x00, count: 56) // header (zeros)

        // Add 2 addresses
        let addr1Data = Data(repeating: 0xAA, count: 32)
        let addr2Data = Data(repeating: 0xBB, count: 32)
        altData.append(addr1Data)
        altData.append(addr2Data)

        let alt = try AddressLookupTable.deserialize(key: altKey, data: altData)

        XCTAssertEqual(alt.key, altKey)
        XCTAssertEqual(alt.addresses.count, 2)
        XCTAssertEqual(alt.addresses[0].data, addr1Data)
        XCTAssertEqual(alt.addresses[1].data, addr2Data)
    }

    func testAddressLookupTableDeserializeEmpty() throws {
        let altKey = try SolanaPublicKey(data: Data(repeating: 0xFF, count: 32))

        // Header only, no addresses
        let altData = Data(repeating: 0x00, count: 56)

        let alt = try AddressLookupTable.deserialize(key: altKey, data: altData)

        XCTAssertEqual(alt.key, altKey)
        XCTAssertEqual(alt.addresses.count, 0)
    }

    func testAddressLookupTableDeserializeTooShort() throws {
        let altKey = try SolanaPublicKey(data: Data(repeating: 0xFF, count: 32))
        let altData = Data(repeating: 0x00, count: 30) // too short

        XCTAssertThrowsError(try AddressLookupTable.deserialize(key: altKey, data: altData))
    }

    func testAddressLookupTableDeserializeBadLength() throws {
        let altKey = try SolanaPublicKey(data: Data(repeating: 0xFF, count: 32))
        // 56 bytes header + 10 bytes (not a multiple of 32)
        let altData = Data(repeating: 0x00, count: 66)

        XCTAssertThrowsError(try AddressLookupTable.deserialize(key: altKey, data: altData))
    }
}
