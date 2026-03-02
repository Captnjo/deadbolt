import XCTest
@testable import DeadboltCore

final class MessageTests: XCTestCase {

    /// Test that a simple SOL transfer message serializes with the correct structure.
    func testSimpleTransferMessageStructure() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        // Use a known 32-byte blockhash (Base58 of 32 zero bytes = "11111111111111111111111111111111")
        let blockhashBytes = Data(repeating: 0x00, count: 32)
        let blockhash = Base58.encode(blockhashBytes)

        let transferIx = SystemProgram.transfer(from: feePayer, to: recipient, lamports: 1_000_000)

        let message = try Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: [transferIx]
        )

        // Header checks
        XCTAssertEqual(message.header.numRequiredSignatures, 1) // only fee payer signs
        XCTAssertEqual(message.header.numReadonlySignedAccounts, 0)
        XCTAssertEqual(message.header.numReadonlyUnsignedAccounts, 1) // System program

        // Account keys: fee payer, recipient, System program
        XCTAssertEqual(message.accountKeys.count, 3)
        XCTAssertEqual(message.accountKeys[0], feePayer) // fee payer always first
        XCTAssertEqual(message.accountKeys[1], recipient) // writable non-signer
        XCTAssertEqual(message.accountKeys[2], SystemProgram.programId) // readonly non-signer

        // One compiled instruction
        XCTAssertEqual(message.instructions.count, 1)
        XCTAssertEqual(message.instructions[0].programIdIndex, 2) // System program at index 2
        XCTAssertEqual(message.instructions[0].accountIndices, [0, 1]) // from=0, to=1
    }

    /// Test message serialization produces valid wire format bytes.
    func testMessageSerializationFormat() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhashBytes = Data(repeating: 0xAA, count: 32)
        let blockhash = Base58.encode(blockhashBytes)

        let transferIx = SystemProgram.transfer(from: feePayer, to: recipient, lamports: 100)

        let message = try Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: [transferIx]
        )

        let serialized = message.serialize()

        // Verify structure:
        // [0]: numRequiredSignatures = 1
        // [1]: numReadonlySignedAccounts = 0
        // [2]: numReadonlyUnsignedAccounts = 1
        XCTAssertEqual(serialized[0], 1)
        XCTAssertEqual(serialized[1], 0)
        XCTAssertEqual(serialized[2], 1)

        // [3]: compact-u16 account count = 3 (single byte)
        XCTAssertEqual(serialized[3], 3)

        // [4..36]: fee payer (32 bytes of 0x01)
        XCTAssertEqual(Data(serialized[4..<36]), Data(repeating: 0x01, count: 32))

        // [36..68]: recipient (32 bytes of 0x02)
        XCTAssertEqual(Data(serialized[36..<68]), Data(repeating: 0x02, count: 32))

        // [68..100]: System program ID (32 bytes)
        XCTAssertEqual(Data(serialized[68..<100]), SystemProgram.programId.data)

        // [100..132]: blockhash (32 bytes of 0xAA)
        XCTAssertEqual(Data(serialized[100..<132]), Data(repeating: 0xAA, count: 32))

        // [132]: compact-u16 instruction count = 1
        XCTAssertEqual(serialized[132], 1)

        // [133]: program ID index = 2
        XCTAssertEqual(serialized[133], 2)

        // [134]: compact-u16 account indices count = 2
        XCTAssertEqual(serialized[134], 2)

        // [135]: account index 0 (from)
        XCTAssertEqual(serialized[135], 0)

        // [136]: account index 1 (to)
        XCTAssertEqual(serialized[136], 1)

        // [137]: compact-u16 data length = 12
        XCTAssertEqual(serialized[137], 12)

        // [138..150]: instruction data (12 bytes: u32(2) + u64(100))
        XCTAssertEqual(serialized[138], 2) // transfer instruction
    }

    /// Test that multiple instructions produce correct account ordering and deduplication.
    func testMultipleInstructionsDeduplication() throws {
        let feePayer = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipient = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))
        let blockhash = Base58.encode(Data(repeating: 0x00, count: 32))

        let instructions = [
            ComputeBudgetProgram.setComputeUnitLimit(200_000),
            ComputeBudgetProgram.setComputeUnitPrice(1000),
            SystemProgram.transfer(from: feePayer, to: recipient, lamports: 100),
        ]

        let message = try Message(
            feePayer: feePayer,
            recentBlockhash: blockhash,
            instructions: instructions
        )

        // Fee payer is signer+writable. Recipient is non-signer+writable.
        // System program and ComputeBudget program are non-signer+readonly.
        XCTAssertEqual(message.header.numRequiredSignatures, 1)
        XCTAssertEqual(message.header.numReadonlySignedAccounts, 0)
        XCTAssertEqual(message.header.numReadonlyUnsignedAccounts, 2) // System + ComputeBudget

        // 4 unique accounts: feePayer, recipient, SystemProgram, ComputeBudgetProgram
        XCTAssertEqual(message.accountKeys.count, 4)
        XCTAssertEqual(message.accountKeys[0], feePayer)

        // 3 compiled instructions
        XCTAssertEqual(message.instructions.count, 3)
    }
}
