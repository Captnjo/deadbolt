import Foundation

// MARK: - Transaction Preview

/// A complete preview of a transaction before submission, including balance changes,
/// fee breakdown, simulation status, and warnings.
public struct TransactionPreview: Sendable {
    /// Human-readable description of the transaction action (e.g., "Send 0.5 SOL to ABC...XYZ").
    public let actionDescription: String

    /// Balance changes caused by this transaction.
    public let balanceChanges: [BalanceChange]

    /// Fee breakdown (base fee, priority fee, Jito tip).
    public let feeBreakdown: TransactionFees

    /// Result of transaction simulation.
    public let simulationStatus: SimulationStatus

    /// Warnings detected for this transaction.
    public let warnings: [TransactionWarning]

    public init(
        actionDescription: String,
        balanceChanges: [BalanceChange],
        feeBreakdown: TransactionFees,
        simulationStatus: SimulationStatus,
        warnings: [TransactionWarning]
    ) {
        self.actionDescription = actionDescription
        self.balanceChanges = balanceChanges
        self.feeBreakdown = feeBreakdown
        self.simulationStatus = simulationStatus
        self.warnings = warnings
    }
}

// MARK: - Balance Change

/// Represents a balance change for a single account.
public struct BalanceChange: Sendable, Equatable {
    /// The account whose balance changes.
    public let account: SolanaPublicKey

    /// Change in SOL balance (in lamports, signed). Negative means SOL is deducted.
    public let solChange: Int64

    /// Token balance changes for this account: (mint address, signed amount in smallest units).
    public let tokenChanges: [(mint: String, amount: Int64)]

    public init(account: SolanaPublicKey, solChange: Int64, tokenChanges: [(mint: String, amount: Int64)]) {
        self.account = account
        self.solChange = solChange
        self.tokenChanges = tokenChanges
    }

    public static func == (lhs: BalanceChange, rhs: BalanceChange) -> Bool {
        guard lhs.account == rhs.account && lhs.solChange == rhs.solChange else { return false }
        guard lhs.tokenChanges.count == rhs.tokenChanges.count else { return false }
        for (l, r) in zip(lhs.tokenChanges, rhs.tokenChanges) {
            if l.mint != r.mint || l.amount != r.amount { return false }
        }
        return true
    }
}

// MARK: - Simulation Status

/// The status of a transaction simulation.
public enum SimulationStatus: Sendable, Equatable {
    /// Simulation has not been performed yet.
    case pending
    /// Simulation succeeded.
    case success(unitsConsumed: UInt64)
    /// Simulation failed with an error.
    case failure(error: String)
}

// MARK: - Transaction Warning

/// Warnings that may be raised during transaction preview.
public enum TransactionWarning: Sendable, Equatable {
    /// The recipient address has 0 SOL balance (may be a new/unfunded account).
    case unfundedRecipient
    /// The transfer amount exceeds 50% of the sender's current balance.
    case largeAmount
    /// The transaction uses a program ID that we do not recognize.
    case unrecognizedProgram(programId: String)
    /// The transaction simulation failed.
    case simulationFailed(error: String)
}
