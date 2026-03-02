import XCTest
@testable import DeadboltCore

final class TransactionPreviewTests: XCTestCase {

    // MARK: - TransactionPreview creation from analysis

    func testPreviewFromAnalysis() throws {
        let sender = try SolanaPublicKey(base58: "So11111111111111111111111111111111111111112")
        let recipient = try SolanaPublicKey(base58: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")

        let instructions: [Instruction] = [
            ComputeBudgetProgram.setComputeUnitLimit(200_000),
            ComputeBudgetProgram.setComputeUnitPrice(5000),
            SystemProgram.transfer(from: sender, to: recipient, lamports: 1_000_000_000),
        ]

        let analysis = InstructionAnalyzer.analyze(instructions: instructions)
        let rpcClient = SolanaRPCClient(rpcURL: URL(string: "https://example.com")!)
        let builder = TransactionPreviewBuilder(rpcClient: rpcClient)

        let preview = builder.buildPreviewFromAnalysis(analysis: analysis)

        XCTAssertTrue(preview.actionDescription.contains("SOL"))
        XCTAssertFalse(preview.balanceChanges.isEmpty)
        XCTAssertEqual(preview.feeBreakdown.baseFee, 5000)
        XCTAssertEqual(preview.feeBreakdown.priorityFee, 1000)
        XCTAssertEqual(preview.simulationStatus, .pending)
        XCTAssertTrue(preview.warnings.isEmpty)
    }

    func testPreviewBalanceChanges() throws {
        let sender = try SolanaPublicKey(base58: "So11111111111111111111111111111111111111112")
        let recipient = try SolanaPublicKey(base58: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")

        let instructions: [Instruction] = [
            SystemProgram.transfer(from: sender, to: recipient, lamports: 500_000_000),
        ]

        let analysis = InstructionAnalyzer.analyze(instructions: instructions)
        let rpcClient = SolanaRPCClient(rpcURL: URL(string: "https://example.com")!)
        let builder = TransactionPreviewBuilder(rpcClient: rpcClient)

        let preview = builder.buildPreviewFromAnalysis(analysis: analysis)

        XCTAssertEqual(preview.balanceChanges.count, 2)

        // Find sender's balance change
        let senderChange = preview.balanceChanges.first { $0.account == sender }
        XCTAssertNotNil(senderChange)
        XCTAssertEqual(senderChange?.solChange, -500_000_000)

        // Find recipient's balance change
        let recipientChange = preview.balanceChanges.first { $0.account == recipient }
        XCTAssertNotNil(recipientChange)
        XCTAssertEqual(recipientChange?.solChange, 500_000_000)
    }

    // MARK: - Warning detection

    func testUnrecognizedProgramWarning() throws {
        let unknownProgram = try SolanaPublicKey(base58: "Vote111111111111111111111111111111111111111")
        let instruction = Instruction(
            programId: unknownProgram,
            accounts: [],
            data: Data([1, 2, 3])
        )

        let analysis = InstructionAnalyzer.analyze(instructions: [instruction])

        // Build preview with unrecognized program warnings
        let rpcClient = SolanaRPCClient(rpcURL: URL(string: "https://example.com")!)
        let builder = TransactionPreviewBuilder(rpcClient: rpcClient)

        var warnings: [TransactionWarning] = []
        for programId in analysis.unrecognizedPrograms {
            warnings.append(.unrecognizedProgram(programId: programId))
        }

        let preview = builder.buildPreviewFromAnalysis(
            analysis: analysis,
            warnings: warnings
        )

        XCTAssertFalse(preview.warnings.isEmpty)
        if case .unrecognizedProgram(let pid) = preview.warnings[0] {
            XCTAssertEqual(pid, unknownProgram.base58)
        } else {
            XCTFail("Expected .unrecognizedProgram warning")
        }
    }

    func testLargeAmountWarningCondition() throws {
        // Test the large amount detection logic directly
        let senderAddress = "So11111111111111111111111111111111111111112"
        let senderBalance: UInt64 = 2_000_000_000 // 2 SOL

        let sender = try SolanaPublicKey(base58: senderAddress)
        let recipient = try SolanaPublicKey(base58: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")

        // Transfer 1.5 SOL = 75% of balance -> should trigger warning
        let instructions: [Instruction] = [
            SystemProgram.transfer(from: sender, to: recipient, lamports: 1_500_000_000),
        ]

        let analysis = InstructionAnalyzer.analyze(instructions: instructions)

        // Verify the condition: outflow > 50% of balance
        let senderChange = analysis.solChanges[senderAddress]!
        let outflow = UInt64(abs(senderChange))
        XCTAssertTrue(outflow > senderBalance / 2, "Expected large amount condition to trigger")
    }

    func testSmallAmountNoWarning() throws {
        let senderAddress = "So11111111111111111111111111111111111111112"
        let senderBalance: UInt64 = 10_000_000_000 // 10 SOL

        let sender = try SolanaPublicKey(base58: senderAddress)
        let recipient = try SolanaPublicKey(base58: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")

        // Transfer 0.1 SOL = 1% of balance -> should NOT trigger warning
        let instructions: [Instruction] = [
            SystemProgram.transfer(from: sender, to: recipient, lamports: 100_000_000),
        ]

        let analysis = InstructionAnalyzer.analyze(instructions: instructions)

        let senderChange = analysis.solChanges[senderAddress]!
        let outflow = UInt64(abs(senderChange))
        XCTAssertFalse(outflow > senderBalance / 2, "Expected no large amount condition")
    }

    // MARK: - Fee breakdown

    func testFeeBreakdownCalculation() throws {
        let sender = try SolanaPublicKey(base58: "So11111111111111111111111111111111111111112")
        let recipient = try SolanaPublicKey(base58: "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")
        let tipAccount = try SolanaPublicKey(base58: JitoTip.tipAccounts[0])

        let instructions: [Instruction] = [
            ComputeBudgetProgram.setComputeUnitLimit(200_000),
            ComputeBudgetProgram.setComputeUnitPrice(10_000),
            SystemProgram.transfer(from: sender, to: recipient, lamports: 1_000_000_000),
            SystemProgram.transfer(from: sender, to: tipAccount, lamports: 500_000),
        ]

        let analysis = InstructionAnalyzer.analyze(instructions: instructions)
        let rpcClient = SolanaRPCClient(rpcURL: URL(string: "https://example.com")!)
        let builder = TransactionPreviewBuilder(rpcClient: rpcClient)

        let preview = builder.buildPreviewFromAnalysis(analysis: analysis)

        XCTAssertEqual(preview.feeBreakdown.baseFee, 5000)
        XCTAssertEqual(preview.feeBreakdown.priorityFee, 2000) // 200K * 10K / 1M
        XCTAssertEqual(preview.feeBreakdown.tipAmount, 500_000)
        XCTAssertEqual(preview.feeBreakdown.totalFee, 507_000)
    }

    // MARK: - SimulationStatus

    func testSimulationStatusPending() {
        XCTAssertEqual(SimulationStatus.pending, SimulationStatus.pending)
    }

    func testSimulationStatusSuccess() {
        let status = SimulationStatus.success(unitsConsumed: 50000)
        if case .success(let units) = status {
            XCTAssertEqual(units, 50000)
        } else {
            XCTFail("Expected .success")
        }
    }

    func testSimulationStatusFailure() {
        let status = SimulationStatus.failure(error: "InsufficientFunds")
        if case .failure(let error) = status {
            XCTAssertEqual(error, "InsufficientFunds")
        } else {
            XCTFail("Expected .failure")
        }
    }

    // MARK: - TransactionWarning equatable

    func testTransactionWarningEquatable() {
        XCTAssertEqual(TransactionWarning.unfundedRecipient, TransactionWarning.unfundedRecipient)
        XCTAssertEqual(TransactionWarning.largeAmount, TransactionWarning.largeAmount)
        XCTAssertNotEqual(TransactionWarning.unfundedRecipient, TransactionWarning.largeAmount)

        let w1 = TransactionWarning.unrecognizedProgram(programId: "abc")
        let w2 = TransactionWarning.unrecognizedProgram(programId: "abc")
        let w3 = TransactionWarning.unrecognizedProgram(programId: "xyz")
        XCTAssertEqual(w1, w2)
        XCTAssertNotEqual(w1, w3)
    }
}
