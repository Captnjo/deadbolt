import XCTest
@testable import DeadboltCore

/// P9-004: Comprehensive unit tests for the Solana module.
/// Covers CompactU16 boundary values, Message serialization, all program instruction encodings,
/// PDA derivation, and Transaction serialize/deserialize round-trips.
final class SolanaComprehensiveTests: XCTestCase {

    // MARK: - Helpers

    private func hexToData(_ hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteStr = hex[index..<nextIndex]
            if let byte = UInt8(byteStr, radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        return data
    }

    // MARK: - CompactU16 Boundary Values

    func testCompactU16EncodeDecodeZero() throws {
        let encoded = CompactU16.encode(0)
        XCTAssertEqual(encoded, [0x00])
        XCTAssertEqual(encoded.count, 1)
        let (decoded, bytesRead) = try CompactU16.decode(Data(encoded), offset: 0)
        XCTAssertEqual(decoded, 0)
        XCTAssertEqual(bytesRead, 1)
    }

    func testCompactU16EncodeDecodeOne() throws {
        let encoded = CompactU16.encode(1)
        XCTAssertEqual(encoded, [0x01])
        let (decoded, bytesRead) = try CompactU16.decode(Data(encoded), offset: 0)
        XCTAssertEqual(decoded, 1)
        XCTAssertEqual(bytesRead, 1)
    }

    func testCompactU16EncodeDecode127() throws {
        // Maximum value encodable in 1 byte
        let encoded = CompactU16.encode(127)
        XCTAssertEqual(encoded, [0x7F])
        XCTAssertEqual(encoded.count, 1)
        let (decoded, bytesRead) = try CompactU16.decode(Data(encoded), offset: 0)
        XCTAssertEqual(decoded, 127)
        XCTAssertEqual(bytesRead, 1)
    }

    func testCompactU16EncodeDecode128() throws {
        // Minimum value requiring 2 bytes
        let encoded = CompactU16.encode(128)
        XCTAssertEqual(encoded, [0x80, 0x01])
        XCTAssertEqual(encoded.count, 2)
        let (decoded, bytesRead) = try CompactU16.decode(Data(encoded), offset: 0)
        XCTAssertEqual(decoded, 128)
        XCTAssertEqual(bytesRead, 2)
    }

    func testCompactU16EncodeDecode16383() throws {
        // Maximum value encodable in 2 bytes
        let encoded = CompactU16.encode(16383)
        XCTAssertEqual(encoded, [0xFF, 0x7F])
        XCTAssertEqual(encoded.count, 2)
        let (decoded, bytesRead) = try CompactU16.decode(Data(encoded), offset: 0)
        XCTAssertEqual(decoded, 16383)
        XCTAssertEqual(bytesRead, 2)
    }

    func testCompactU16EncodeDecode16384() throws {
        // Minimum value requiring 3 bytes
        let encoded = CompactU16.encode(16384)
        XCTAssertEqual(encoded, [0x80, 0x80, 0x01])
        XCTAssertEqual(encoded.count, 3)
        let (decoded, bytesRead) = try CompactU16.decode(Data(encoded), offset: 0)
        XCTAssertEqual(decoded, 16384)
        XCTAssertEqual(bytesRead, 3)
    }

    func testCompactU16EncodeDecodeMaxUInt16() throws {
        let encoded = CompactU16.encode(65535)
        XCTAssertEqual(encoded, [0xFF, 0xFF, 0x03])
        XCTAssertEqual(encoded.count, 3)
        let (decoded, bytesRead) = try CompactU16.decode(Data(encoded), offset: 0)
        XCTAssertEqual(decoded, 65535)
        XCTAssertEqual(bytesRead, 3)
    }

    // MARK: - Message Serialization

    func testMessageWithSingleTransferInstruction() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0xAA, count: 32))

        let ix = SystemProgram.transfer(from: feePayer, to: recipient, lamports: 1_000_000)
        let message = try Message(feePayer: feePayer, recentBlockhash: blockhash, instructions: [ix])

        // Header checks
        XCTAssertEqual(message.header.numRequiredSignatures, 1)
        XCTAssertEqual(message.header.numReadonlySignedAccounts, 0)
        XCTAssertEqual(message.header.numReadonlyUnsignedAccounts, 1) // System program

        // Account keys: feePayer, recipient, system program
        XCTAssertEqual(message.accountKeys.count, 3)
        XCTAssertEqual(message.accountKeys[0], feePayer)

        // Instructions
        XCTAssertEqual(message.instructions.count, 1)

        // Serialize + deserialize round-trip
        let serialized = message.serialize()
        var offset = 0
        let deserialized = try Message(deserializing: serialized, offset: &offset)
        XCTAssertEqual(deserialized.serialize(), serialized)
    }

    func testMessageWithMultipleInstructions() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0xBB, count: 32))

        let instructions = [
            ComputeBudgetProgram.setComputeUnitLimit(200_000),
            ComputeBudgetProgram.setComputeUnitPrice(50_000),
            SystemProgram.transfer(from: feePayer, to: recipient, lamports: 500_000),
        ]

        let message = try Message(feePayer: feePayer, recentBlockhash: blockhash, instructions: instructions)

        // Should have 3 compiled instructions
        XCTAssertEqual(message.instructions.count, 3)

        // Account keys: feePayer, recipient, ComputeBudget program, System program
        XCTAssertEqual(message.accountKeys.count, 4)

        // Serialize + deserialize round-trip
        let serialized = message.serialize()
        var offset = 0
        let deserialized = try Message(deserializing: serialized, offset: &offset)
        XCTAssertEqual(deserialized.serialize(), serialized)
    }

    func testMessageWithMaxAccountsDeduplication() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0xCC, count: 32))

        // Two transfers to the same recipient should not duplicate accounts
        let instructions = [
            SystemProgram.transfer(from: feePayer, to: recipient, lamports: 100),
            SystemProgram.transfer(from: feePayer, to: recipient, lamports: 200),
        ]

        let message = try Message(feePayer: feePayer, recentBlockhash: blockhash, instructions: instructions)

        // Still just 3 unique accounts: feePayer, recipient, system program
        XCTAssertEqual(message.accountKeys.count, 3)
        XCTAssertEqual(message.instructions.count, 2)
    }

    // MARK: - Program Instruction Encodings

    func testSystemProgramTransferEncoding() throws {
        let from = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let to = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let ix = SystemProgram.transfer(from: from, to: to, lamports: 1_000_000)

        XCTAssertEqual(ix.programId, SystemProgram.programId)
        XCTAssertEqual(ix.accounts.count, 2)
        XCTAssertTrue(ix.accounts[0].isSigner)
        XCTAssertTrue(ix.accounts[0].isWritable)
        XCTAssertFalse(ix.accounts[1].isSigner)
        XCTAssertTrue(ix.accounts[1].isWritable)

        // Data: 4 bytes instruction index (2 = transfer) + 8 bytes lamports
        XCTAssertEqual(ix.data.count, 12)
        // First 4 bytes should be instruction index 2 (LE)
        XCTAssertEqual(ix.data[0], 2)
        XCTAssertEqual(ix.data[1], 0)
        XCTAssertEqual(ix.data[2], 0)
        XCTAssertEqual(ix.data[3], 0)
        // Last 8 bytes = 1_000_000 in little-endian
        var lamports: UInt64 = 0
        withUnsafeMutableBytes(of: &lamports) { ptr in
            ix.data.copyBytes(to: ptr.bindMemory(to: UInt8.self), from: 4..<12)
        }
        XCTAssertEqual(lamports, 1_000_000)
    }

    func testComputeBudgetSetComputeUnitLimitEncoding() {
        let ix = ComputeBudgetProgram.setComputeUnitLimit(200_000)

        XCTAssertEqual(ix.programId, ComputeBudgetProgram.programId)
        XCTAssertEqual(ix.accounts.count, 0)
        XCTAssertEqual(ix.data.count, 5)
        XCTAssertEqual(ix.data[0], 2) // SetComputeUnitLimit instruction type

        var units: UInt32 = 0
        withUnsafeMutableBytes(of: &units) { ptr in
            ix.data.copyBytes(to: ptr.bindMemory(to: UInt8.self), from: 1..<5)
        }
        XCTAssertEqual(units, 200_000)
    }

    func testComputeBudgetSetComputeUnitPriceEncoding() {
        let ix = ComputeBudgetProgram.setComputeUnitPrice(50_000)

        XCTAssertEqual(ix.programId, ComputeBudgetProgram.programId)
        XCTAssertEqual(ix.accounts.count, 0)
        XCTAssertEqual(ix.data.count, 9)
        XCTAssertEqual(ix.data[0], 3) // SetComputeUnitPrice instruction type

        var price: UInt64 = 0
        withUnsafeMutableBytes(of: &price) { ptr in
            ix.data.copyBytes(to: ptr.bindMemory(to: UInt8.self), from: 1..<9)
        }
        XCTAssertEqual(price, 50_000)
    }

    func testTokenProgramTransferEncoding() throws {
        let source = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let dest = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let owner = try SolanaPublicKey(data: Data(repeating: 0x03, count: 32))

        let ix = TokenProgram.transfer(source: source, destination: dest, owner: owner, amount: 5_000_000)

        XCTAssertEqual(ix.programId, TokenProgram.programId)
        XCTAssertEqual(ix.accounts.count, 3)
        // source is writable
        XCTAssertTrue(ix.accounts[0].isWritable)
        XCTAssertFalse(ix.accounts[0].isSigner)
        // dest is writable
        XCTAssertTrue(ix.accounts[1].isWritable)
        XCTAssertFalse(ix.accounts[1].isSigner)
        // owner is signer
        XCTAssertTrue(ix.accounts[2].isSigner)
        XCTAssertFalse(ix.accounts[2].isWritable)

        // Data: u8(3) + u64 amount
        XCTAssertEqual(ix.data.count, 9)
        XCTAssertEqual(ix.data[0], 3) // Transfer variant

        var amount: UInt64 = 0
        withUnsafeMutableBytes(of: &amount) { ptr in
            ix.data.copyBytes(to: ptr.bindMemory(to: UInt8.self), from: 1..<9)
        }
        XCTAssertEqual(amount, 5_000_000)
    }

    func testTokenProgramCreateATAInstruction() throws {
        let payer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let owner = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let mint = try SolanaPublicKey(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")

        let ix = try TokenProgram.createAssociatedTokenAccount(payer: payer, owner: owner, mint: mint)

        XCTAssertEqual(ix.programId, TokenProgram.associatedTokenProgramId)
        XCTAssertEqual(ix.accounts.count, 6)
        XCTAssertEqual(ix.data.count, 0) // ATA creation has no instruction data

        // payer is signer + writable
        XCTAssertTrue(ix.accounts[0].isSigner)
        XCTAssertTrue(ix.accounts[0].isWritable)
        // ATA account is writable
        XCTAssertTrue(ix.accounts[1].isWritable)
        XCTAssertFalse(ix.accounts[1].isSigner)
    }

    func testJitoTipInstructionEncoding() throws {
        let from = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let ix = try JitoTip.tipInstruction(from: from, lamports: JitoTip.defaultTipLamports)

        // It's a SystemProgram.transfer under the hood
        XCTAssertEqual(ix.programId, SystemProgram.programId)
        XCTAssertEqual(ix.accounts.count, 2)
        XCTAssertEqual(ix.data.count, 12)

        // Verify the tip account is one of the known Jito accounts
        let tipAccountBase58 = ix.accounts[1].publicKey.base58
        XCTAssertTrue(JitoTip.tipAccounts.contains(tipAccountBase58),
                      "Tip account \(tipAccountBase58) should be in the known Jito tip accounts")
    }

    // MARK: - PDA Derivation

    func testPDADerivationKnownATAVector() throws {
        // Known wallet and mint should produce deterministic ATA
        let wallet = try SolanaPublicKey(base58: "7fUAJdStEuGbc3sM84cKRL6yYaaSstyLSU4ve21asR2r")
        let usdcMint = try SolanaPublicKey(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")

        let ata = try SolanaPublicKey.associatedTokenAddress(owner: wallet, mint: usdcMint)
        XCTAssertEqual(ata.base58, "FEEHnCYLSjT7QZJvNoNiuFABCpAwvvZjZ4ak5dAaU636")
    }

    func testPDABumpSeedVerification() throws {
        let programId = try SolanaPublicKey(base58: "11111111111111111111111111111111")
        let seed = Data("test_bump".utf8)

        let (address, bump) = try SolanaPublicKey.findProgramAddress(seeds: [seed], programId: programId)

        // Recreate with explicit bump
        let recreated = try SolanaPublicKey.createProgramAddress(
            seeds: [seed, Data([bump])],
            programId: programId
        )
        XCTAssertEqual(address, recreated)

        // Bump should be between 0 and 255
        XCTAssertTrue(bump <= 255)

        // The address should NOT be on the Ed25519 curve
        XCTAssertFalse(Ed25519CurveCheck.isOnCurve(address.data))
    }

    // MARK: - Transaction Serialize/Deserialize Round-Trip

    func testTransactionSerializeDeserializeRoundTrip() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0xDD, count: 32))

        let message = try Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: [SystemProgram.transfer(from: feePayer, to: recipient, lamports: 42)]
        )

        let tx = Transaction(message: message)
        let serialized = tx.serialize()

        // Verify we can parse the serialized data
        // First byte is compact-u16 signature count (1)
        XCTAssertEqual(serialized[0], 1)

        // Next 64 bytes are the zero-filled signature
        let sigSlice = serialized[1..<65]
        XCTAssertEqual(Data(sigSlice), Data(repeating: 0, count: 64))

        // Base64 round-trip
        let base64 = tx.serializeBase64()
        let decoded = Data(base64Encoded: base64)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded, serialized)
    }

    func testSignedTransactionRoundTrip() async throws {
        let signer = try SoftwareSigner(seed: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0xEE, count: 32))

        let message = try Message(
            feePayer: signer.publicKey,
            recentBlockhash: blockhash,
            instructions: [SystemProgram.transfer(from: signer.publicKey, to: recipient, lamports: 100)]
        )

        var tx = Transaction(message: message)
        try await tx.sign(with: signer)

        // Signature should not be all zeros
        XCTAssertNotEqual(tx.signatures[0], Data(repeating: 0, count: 64))

        // Verify the signature
        let messageData = message.serialize()
        let isValid = SoftwareSigner.verify(
            signature: tx.signatures[0],
            message: messageData,
            publicKey: signer.publicKey
        )
        XCTAssertTrue(isValid, "Transaction signature should verify against message bytes")
    }

    func testTransactionWithComputeBudgetInstructions() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0xFF, count: 32))

        let message = try Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: [
                ComputeBudgetProgram.setComputeUnitLimit(300_000),
                ComputeBudgetProgram.setComputeUnitPrice(100_000),
                SystemProgram.transfer(from: feePayer, to: recipient, lamports: 1_000),
            ]
        )

        let tx = Transaction(message: message)
        XCTAssertEqual(tx.signatures.count, 1) // Only fee payer signs
        XCTAssertEqual(message.instructions.count, 3)

        // Serialize and verify non-empty
        let serialized = tx.serialize()
        XCTAssertTrue(serialized.count > 100) // Should be a reasonable size
    }

    // MARK: - SolanaPublicKey

    func testSolanaPublicKeyFromBase58() throws {
        let key = try SolanaPublicKey(base58: "11111111111111111111111111111111")
        XCTAssertEqual(key.data, Data(repeating: 0, count: 32))
    }

    func testSolanaPublicKeyInvalidLength() {
        XCTAssertThrowsError(try SolanaPublicKey(data: Data(repeating: 0, count: 31))) { error in
            guard case SolanaError.invalidPublicKeyLength(let n) = error else {
                XCTFail("Expected invalidPublicKeyLength, got \(error)")
                return
            }
            XCTAssertEqual(n, 31)
        }
    }

    func testSolanaPublicKeyShortAddress() throws {
        let key = try SolanaPublicKey(base58: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
        XCTAssertEqual(key.shortAddress, "Toke...Q5DA")
    }

    func testSolanaPublicKeyCodable() throws {
        let original = try SolanaPublicKey(base58: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SolanaPublicKey.self, from: encoded)
        XCTAssertEqual(original, decoded)
    }
}
