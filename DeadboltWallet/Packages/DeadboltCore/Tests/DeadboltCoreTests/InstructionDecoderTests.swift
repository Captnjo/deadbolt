import XCTest
@testable import DeadboltCore

final class InstructionDecoderTests: XCTestCase {

    // MARK: - Single Instruction Decoding

    func testDecodeInstructionProgramId() throws {
        let jupiterIx = JupiterInstructionData(
            programId: "11111111111111111111111111111111",
            accounts: [],
            data: Data([0x01]).base64EncodedString()
        )

        let instruction = try InstructionDecoder.decode(jupiterIx)

        XCTAssertEqual(instruction.programId, SystemProgram.programId)
    }

    func testDecodeInstructionAccounts() throws {
        let feePayerKey = try SolanaPublicKey(data: Data(repeating: 0x01, count: 32))
        let recipientKey = try SolanaPublicKey(data: Data(repeating: 0x02, count: 32))

        let jupiterIx = JupiterInstructionData(
            programId: "11111111111111111111111111111111",
            accounts: [
                JupiterAccountData(pubkey: feePayerKey.base58, isSigner: true, isWritable: true),
                JupiterAccountData(pubkey: recipientKey.base58, isSigner: false, isWritable: true),
            ],
            data: Data([0x01]).base64EncodedString()
        )

        let instruction = try InstructionDecoder.decode(jupiterIx)

        XCTAssertEqual(instruction.accounts.count, 2)
        XCTAssertEqual(instruction.accounts[0].publicKey, feePayerKey)
        XCTAssertTrue(instruction.accounts[0].isSigner)
        XCTAssertTrue(instruction.accounts[0].isWritable)
        XCTAssertEqual(instruction.accounts[1].publicKey, recipientKey)
        XCTAssertFalse(instruction.accounts[1].isSigner)
        XCTAssertTrue(instruction.accounts[1].isWritable)
    }

    func testDecodeInstructionData() throws {
        let originalData = Data([0x02, 0x00, 0x00, 0x00, 0x40, 0x42, 0x0F, 0x00, 0x00, 0x00, 0x00, 0x00])
        let base64Data = originalData.base64EncodedString()

        let jupiterIx = JupiterInstructionData(
            programId: "11111111111111111111111111111111",
            accounts: [],
            data: base64Data
        )

        let instruction = try InstructionDecoder.decode(jupiterIx)

        XCTAssertEqual(instruction.data, originalData)
    }

    func testDecodeInvalidBase64Throws() {
        let jupiterIx = JupiterInstructionData(
            programId: "11111111111111111111111111111111",
            accounts: [],
            data: "not-valid-base64!!!"
        )

        XCTAssertThrowsError(try InstructionDecoder.decode(jupiterIx)) { error in
            guard let solanaError = error as? SolanaError,
                  case .decodingError(let msg) = solanaError else {
                XCTFail("Expected SolanaError.decodingError, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("base64"))
        }
    }

    // MARK: - Multiple Instructions Decoding

    func testDecodeAllInstructions() throws {
        // Simulate two compute budget instructions
        let limitData = Data([0x02, 0x40, 0x0D, 0x03, 0x00]) // SetComputeUnitLimit(200_000)
        let priceData = Data([0x03, 0xE8, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) // SetComputeUnitPrice(1000)

        let jupiterIxs = [
            JupiterInstructionData(
                programId: "ComputeBudget111111111111111111111111111111",
                accounts: [],
                data: limitData.base64EncodedString()
            ),
            JupiterInstructionData(
                programId: "ComputeBudget111111111111111111111111111111",
                accounts: [],
                data: priceData.base64EncodedString()
            ),
        ]

        let instructions = try InstructionDecoder.decodeAll(jupiterIxs)

        XCTAssertEqual(instructions.count, 2)
        XCTAssertEqual(instructions[0].programId, ComputeBudgetProgram.programId)
        XCTAssertEqual(instructions[1].programId, ComputeBudgetProgram.programId)
        XCTAssertEqual(instructions[0].data, limitData)
        XCTAssertEqual(instructions[1].data, priceData)
    }

    func testDecodeAllEmptyArray() throws {
        let instructions = try InstructionDecoder.decodeAll([])
        XCTAssertTrue(instructions.isEmpty)
    }

    func testDecodeComputeBudgetInstruction() throws {
        // This is what Jupiter actually returns for SetComputeUnitLimit(120000)
        var limitData = Data(count: 5)
        limitData[0] = 2
        var limit: UInt32 = 120_000
        withUnsafeBytes(of: &limit) { bytes in
            limitData.replaceSubrange(1..<5, with: bytes)
        }

        let jupiterIx = JupiterInstructionData(
            programId: "ComputeBudget111111111111111111111111111111",
            accounts: [],
            data: limitData.base64EncodedString()
        )

        let instruction = try InstructionDecoder.decode(jupiterIx)

        // Verify we get the same result as building with ComputeBudgetProgram directly
        let expected = ComputeBudgetProgram.setComputeUnitLimit(120_000)
        XCTAssertEqual(instruction.programId, expected.programId)
        XCTAssertEqual(instruction.data, expected.data)
        XCTAssertEqual(instruction.accounts.count, expected.accounts.count)
    }
}
