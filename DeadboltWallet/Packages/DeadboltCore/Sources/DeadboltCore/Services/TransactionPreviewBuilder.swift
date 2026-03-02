import Foundation

/// Builds a complete TransactionPreview by combining instruction analysis,
/// transaction simulation, and warning detection.
public actor TransactionPreviewBuilder {
    private let rpcClient: SolanaRPCClient

    public init(rpcClient: SolanaRPCClient) {
        self.rpcClient = rpcClient
    }

    /// Build a TransactionPreview from a list of instructions and optional simulation.
    ///
    /// - Parameters:
    ///   - instructions: The transaction instructions to analyze.
    ///   - encodedTransaction: Optional base64-encoded signed transaction for simulation.
    ///   - senderAddress: The sender's wallet address (for balance-based warnings).
    ///   - senderBalance: The sender's current SOL balance in lamports (for large amount detection).
    /// - Returns: A complete TransactionPreview.
    public func buildPreview(
        instructions: [Instruction],
        encodedTransaction: String? = nil,
        senderAddress: String? = nil,
        senderBalance: UInt64? = nil
    ) async -> TransactionPreview {
        // 1. Analyze instructions locally
        let analysis = InstructionAnalyzer.analyze(instructions: instructions)

        // 2. Build balance changes
        let balanceChanges = buildBalanceChanges(from: analysis)

        // 3. Run simulation if we have an encoded transaction
        let simulationStatus: SimulationStatus
        if let encoded = encodedTransaction {
            simulationStatus = await runSimulation(encodedTransaction: encoded)
        } else {
            simulationStatus = .pending
        }

        // 4. Detect warnings
        let warnings = await detectWarnings(
            analysis: analysis,
            simulationStatus: simulationStatus,
            senderAddress: senderAddress,
            senderBalance: senderBalance
        )

        return TransactionPreview(
            actionDescription: analysis.actionDescription,
            balanceChanges: balanceChanges,
            feeBreakdown: analysis.fees,
            simulationStatus: simulationStatus,
            warnings: warnings
        )
    }

    /// Build a TransactionPreview from pre-analyzed results (no RPC calls needed for basic preview).
    public nonisolated func buildPreviewFromAnalysis(
        analysis: InstructionAnalyzer.AnalysisResult,
        simulationStatus: SimulationStatus = .pending,
        warnings: [TransactionWarning] = []
    ) -> TransactionPreview {
        let balanceChanges = buildBalanceChanges(from: analysis)

        return TransactionPreview(
            actionDescription: analysis.actionDescription,
            balanceChanges: balanceChanges,
            feeBreakdown: analysis.fees,
            simulationStatus: simulationStatus,
            warnings: warnings
        )
    }

    // MARK: - Balance Changes

    private nonisolated func buildBalanceChanges(from analysis: InstructionAnalyzer.AnalysisResult) -> [BalanceChange] {
        // Collect all accounts that have any changes
        var allAccounts = Set<String>()
        for key in analysis.solChanges.keys { allAccounts.insert(key) }
        for key in analysis.tokenChanges.keys { allAccounts.insert(key) }

        var changes: [BalanceChange] = []
        for account in allAccounts.sorted() {
            guard let pubkey = try? SolanaPublicKey(base58: account) else { continue }
            let solChange = analysis.solChanges[account] ?? 0
            let tokenChangeList = analysis.tokenChanges[account] ?? []

            changes.append(BalanceChange(
                account: pubkey,
                solChange: solChange,
                tokenChanges: tokenChangeList
            ))
        }

        return changes
    }

    // MARK: - Simulation

    private func runSimulation(encodedTransaction: String) async -> SimulationStatus {
        do {
            let result = try await rpcClient.simulateTransaction(encodedTransaction: encodedTransaction)
            if let err = result.err {
                let errorStr: String
                switch err {
                case .string(let s): errorStr = s
                case .object(let obj): errorStr = obj.description
                }
                return .failure(error: errorStr)
            }
            return .success(unitsConsumed: result.unitsConsumed ?? 0)
        } catch {
            return .failure(error: error.localizedDescription)
        }
    }

    // MARK: - Warning Detection

    private func detectWarnings(
        analysis: InstructionAnalyzer.AnalysisResult,
        simulationStatus: SimulationStatus,
        senderAddress: String?,
        senderBalance: UInt64?
    ) async -> [TransactionWarning] {
        var warnings: [TransactionWarning] = []

        // 1. Unrecognized programs
        for programId in analysis.unrecognizedPrograms {
            warnings.append(.unrecognizedProgram(programId: programId))
        }

        // 2. Simulation failed
        if case .failure(let error) = simulationStatus {
            warnings.append(.simulationFailed(error: error))
        }

        // 3. Large amount detection
        if let senderAddr = senderAddress, let balance = senderBalance {
            // Sum up all SOL outflows for the sender
            if let senderChange = analysis.solChanges[senderAddr], senderChange < 0 {
                let outflow = UInt64(abs(senderChange))
                // Warn if outflow > 50% of balance (including fees and tips)
                if outflow > balance / 2 {
                    warnings.append(.largeAmount)
                }
            }
        }

        // 4. Unfunded recipient detection
        // Check SOL recipients (positive balance changes, excluding known Jito tip accounts)
        for (account, change) in analysis.solChanges where change > 0 {
            // Skip Jito tip accounts
            if InstructionAnalyzer.jitoTipAccounts.contains(account) { continue }
            // Skip sender's own account
            if account == senderAddress { continue }

            do {
                let recipientBalance = try await rpcClient.getBalance(address: account)
                if recipientBalance == 0 {
                    warnings.append(.unfundedRecipient)
                    break // Only warn once
                }
            } catch {
                // If we can't check balance, skip this warning
            }
        }

        return warnings
    }
}
