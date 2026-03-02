import XCTest
@testable import DeadboltCore

final class InstructionAnalyzerTests: XCTestCase {

    // MARK: - SystemProgram.transfer detection

    func testSystemTransferDetection() throws {
        let from = try SolanaPublicKey(base58: "So11111111111111111111111111111111111111112")
        let to = try SolanaPublicKey(base58: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")
        let lamports: UInt64 = 500_000_000 // 0.5 SOL

        let instruction = SystemProgram.transfer(from: from, to: to, lamports: lamports)
        let result = InstructionAnalyzer.analyze(instructions: [instruction])

        // Check SOL changes
        XCTAssertEqual(result.solChanges[from.base58], -500_000_000)
        XCTAssertEqual(result.solChanges[to.base58], 500_000_000)

        // Should mention sending SOL
        XCTAssertTrue(result.actionDescription.contains("SOL"))
        XCTAssertFalse(result.hasJitoTip)
        XCTAssertTrue(result.unrecognizedPrograms.isEmpty)
    }

    func testSystemTransferBalanceChanges() throws {
        let from = try SolanaPublicKey(base58: "So11111111111111111111111111111111111111112")
        let to = try SolanaPublicKey(base58: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")
        let lamports: UInt64 = 1_000_000_000 // 1 SOL

        let instruction = SystemProgram.transfer(from: from, to: to, lamports: lamports)
        let result = InstructionAnalyzer.analyze(instructions: [instruction])

        // From account should lose lamports
        XCTAssertEqual(result.solChanges[from.base58], -1_000_000_000)
        // To account should gain lamports
        XCTAssertEqual(result.solChanges[to.base58], 1_000_000_000)
    }

    // MARK: - SPL Token transfer detection

    func testSPLTokenTransferDetection() throws {
        let source = try SolanaPublicKey(base58: "So11111111111111111111111111111111111111112")
        let destination = try SolanaPublicKey(base58: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")
        let owner = try SolanaPublicKey(base58: "GsbwXfJraMomNxBcjYLcG3mxkBUiyWXAB32fGbSQQRKJ")
        let amount: UInt64 = 1_000_000 // 1 USDC (6 decimals)

        let instruction = TokenProgram.transfer(
            source: source,
            destination: destination,
            owner: owner,
            amount: amount
        )
        let result = InstructionAnalyzer.analyze(instructions: [instruction])

        // Token changes should be tracked
        let sourceChanges = result.tokenChanges[source.base58]
        XCTAssertNotNil(sourceChanges)
        XCTAssertEqual(sourceChanges?.first?.amount, -1_000_000)

        let destChanges = result.tokenChanges[destination.base58]
        XCTAssertNotNil(destChanges)
        XCTAssertEqual(destChanges?.first?.amount, 1_000_000)

        XCTAssertTrue(result.actionDescription.contains("tokens"))
    }

    // MARK: - ComputeBudget instruction parsing

    func testComputeUnitLimitDetection() throws {
        let instruction = ComputeBudgetProgram.setComputeUnitLimit(300_000)
        let result = InstructionAnalyzer.analyze(instructions: [instruction])

        // ComputeBudget doesn't generate balance changes directly, but affects fee calculation
        // The fee should use the detected compute unit limit
        XCTAssertTrue(result.solChanges.isEmpty)
    }

    func testComputeUnitPriceDetection() throws {
        let limitIx = ComputeBudgetProgram.setComputeUnitLimit(200_000)
        let priceIx = ComputeBudgetProgram.setComputeUnitPrice(5000) // 5000 micro-lamports

        let result = InstructionAnalyzer.analyze(instructions: [limitIx, priceIx])

        // Priority fee = 200,000 * 5000 / 1,000,000 = 1000 lamports
        XCTAssertEqual(result.fees.priorityFee, 1000)
        XCTAssertEqual(result.fees.baseFee, 5000)
    }

    func testComputeBudgetFeeCalculation() throws {
        let limitIx = ComputeBudgetProgram.setComputeUnitLimit(400_000)
        let priceIx = ComputeBudgetProgram.setComputeUnitPrice(10_000) // 10,000 micro-lamports

        let result = InstructionAnalyzer.analyze(instructions: [limitIx, priceIx])

        // Priority fee = 400,000 * 10,000 / 1,000,000 = 4000 lamports
        XCTAssertEqual(result.fees.priorityFee, 4000)
        XCTAssertEqual(result.fees.baseFee, 5000)
        XCTAssertEqual(result.fees.totalFee, 9000) // base + priority, no tip
    }

    // MARK: - Jito tip detection

    func testJitoTipDetection() throws {
        let from = try SolanaPublicKey(base58: "So11111111111111111111111111111111111111112")
        let tipAccount = try SolanaPublicKey(base58: JitoTip.tipAccounts[0])
        let tipLamports: UInt64 = 840_000

        let instruction = SystemProgram.transfer(from: from, to: tipAccount, lamports: tipLamports)
        let result = InstructionAnalyzer.analyze(instructions: [instruction])

        XCTAssertTrue(result.hasJitoTip)
        XCTAssertEqual(result.jitoTipLamports, 840_000)
        XCTAssertEqual(result.fees.tipAmount, 840_000)

        // Jito tip should deduct SOL from sender
        XCTAssertEqual(result.solChanges[from.base58], -840_000)
        // Jito tip account should NOT appear in solChanges (it's filtered to .jitoTip case)
        XCTAssertNil(result.solChanges[tipAccount.base58])
    }

    func testAllJitoTipAccountsRecognized() throws {
        let from = try SolanaPublicKey(base58: "So11111111111111111111111111111111111111112")

        for tipAccountStr in JitoTip.tipAccounts {
            let tipAccount = try SolanaPublicKey(base58: tipAccountStr)
            let instruction = SystemProgram.transfer(from: from, to: tipAccount, lamports: 1000)
            let result = InstructionAnalyzer.analyze(instructions: [instruction])
            XCTAssertTrue(result.hasJitoTip, "Jito tip account not recognized: \(tipAccountStr)")
        }
    }

    // MARK: - Combined instruction set

    func testCombinedTransferWithComputeBudgetAndTip() throws {
        let sender = try SolanaPublicKey(base58: "So11111111111111111111111111111111111111112")
        let recipient = try SolanaPublicKey(base58: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")
        let tipAccount = try SolanaPublicKey(base58: JitoTip.tipAccounts[0])

        let instructions: [Instruction] = [
            ComputeBudgetProgram.setComputeUnitLimit(200_000),
            ComputeBudgetProgram.setComputeUnitPrice(5000),
            SystemProgram.transfer(from: sender, to: recipient, lamports: 1_000_000_000),
            SystemProgram.transfer(from: sender, to: tipAccount, lamports: 840_000),
        ]

        let result = InstructionAnalyzer.analyze(instructions: instructions)

        // Balance changes
        // Sender: -1B (transfer) - 840K (tip) = -1,000,840,000
        XCTAssertEqual(result.solChanges[sender.base58], -1_000_840_000)
        // Recipient: +1B
        XCTAssertEqual(result.solChanges[recipient.base58], 1_000_000_000)

        // Fees
        XCTAssertEqual(result.fees.baseFee, 5000)
        XCTAssertEqual(result.fees.priorityFee, 1000) // 200K * 5000 / 1M
        XCTAssertEqual(result.fees.tipAmount, 840_000)
        XCTAssertEqual(result.fees.totalFee, 846_000)

        // Jito tip
        XCTAssertTrue(result.hasJitoTip)
        XCTAssertEqual(result.jitoTipLamports, 840_000)

        // No unrecognized programs
        XCTAssertTrue(result.unrecognizedPrograms.isEmpty)
    }

    // MARK: - Unrecognized program detection

    func testUnrecognizedProgramDetection() throws {
        let unknownProgramId = try SolanaPublicKey(base58: "Vote111111111111111111111111111111111111111")
        let instruction = Instruction(
            programId: unknownProgramId,
            accounts: [],
            data: Data([1, 2, 3])
        )

        let result = InstructionAnalyzer.analyze(instructions: [instruction])

        XCTAssertFalse(result.unrecognizedPrograms.isEmpty)
        XCTAssertTrue(result.unrecognizedPrograms.contains(unknownProgramId.base58))
    }

    func testKnownProgramsNotUnrecognized() throws {
        let instructions: [Instruction] = [
            ComputeBudgetProgram.setComputeUnitLimit(200_000),
            ComputeBudgetProgram.setComputeUnitPrice(1000),
        ]

        let result = InstructionAnalyzer.analyze(instructions: instructions)
        XCTAssertTrue(result.unrecognizedPrograms.isEmpty)
    }

    // MARK: - Edge cases

    func testEmptyInstructions() {
        let result = InstructionAnalyzer.analyze(instructions: [])

        XCTAssertEqual(result.actionDescription, "Unknown transaction")
        XCTAssertTrue(result.solChanges.isEmpty)
        XCTAssertTrue(result.tokenChanges.isEmpty)
        XCTAssertEqual(result.fees.baseFee, 5000)
        XCTAssertEqual(result.fees.priorityFee, 0)
        XCTAssertEqual(result.fees.tipAmount, 0)
    }

    func testMalformedInstructionData() throws {
        // SystemProgram instruction with too-short data
        let instruction = Instruction(
            programId: SystemProgram.programId,
            accounts: [],
            data: Data([2, 0]) // Only 2 bytes instead of 12
        )

        let result = InstructionAnalyzer.analyze(instructions: [instruction])
        // Should not crash, just treat as unrecognized
        XCTAssertTrue(result.solChanges.isEmpty)
    }
}
