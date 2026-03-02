import SwiftUI
import DeadboltCore

/// P7-005: Unified transaction preview that accepts a TransactionPreview model.
/// Supports all transaction types: send SOL, send token, send NFT, swap, stake.
struct UnifiedTransactionPreviewView: View {
    let preview: TransactionPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transaction Preview")
                .font(.headline)

            Divider()

            // Action description
            infoRow("Action", preview.actionDescription)

            // Balance changes
            if !preview.balanceChanges.isEmpty {
                Divider()
                Text("Balance Changes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(preview.balanceChanges, id: \.account.base58) { change in
                    balanceChangeRow(change)
                }
            }

            Divider()

            // Fee breakdown
            feeSection

            Divider()

            // Simulation status
            simulationBadge

            // Warnings
            if !preview.warnings.isEmpty {
                Divider()
                warningsSection
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Fee Section

    private var feeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            let fees = preview.feeBreakdown
            infoRow("Base Fee", "~\(formatSOL(Double(fees.baseFee) / 1e9)) SOL")
            if fees.priorityFee > 0 {
                infoRow("Priority Fee", "~\(formatSOL(Double(fees.priorityFee) / 1e9)) SOL")
            }
            if fees.tipAmount > 0 {
                infoRow("Jito Tip", "\(formatSOL(Double(fees.tipAmount) / 1e9)) SOL")
            }
            infoRow("Total Fee", "~\(formatSOL(fees.totalSOL)) SOL")
        }
    }

    // MARK: - Simulation Badge

    private var simulationBadge: some View {
        HStack {
            Text("Simulation:")
                .foregroundStyle(.secondary)
            switch preview.simulationStatus {
            case .pending:
                ProgressView()
                    .controlSize(.small)
                Text("Simulating...")
                    .foregroundStyle(.secondary)
            case .success(let cu):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Will succeed (\(cu) CU)")
            case .failure(let error):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(error)
            }
        }
        .font(.caption)
    }

    // MARK: - Warnings

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(preview.warnings.enumerated()), id: \.offset) { _, warning in
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(warningText(warning))
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Helpers

    private func balanceChangeRow(_ change: BalanceChange) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            let shortAddr = shortAddress(change.account.base58)
            if change.solChange != 0 {
                let sign = change.solChange > 0 ? "+" : ""
                let solStr = "\(sign)\(formatSOL(Double(change.solChange) / 1e9)) SOL"
                infoRow(shortAddr, solStr)
            }
            ForEach(change.tokenChanges, id: \.mint) { tokenChange in
                let sign = tokenChange.amount > 0 ? "+" : ""
                let shortMint = shortAddress(tokenChange.mint)
                infoRow(shortAddr, "\(sign)\(tokenChange.amount) \(shortMint)")
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    private func formatSOL(_ sol: Double) -> String {
        DashboardViewModel.formatSOL(UInt64(max(0, sol) * 1_000_000_000))
    }

    private func shortAddress(_ address: String) -> String {
        guard address.count > 8 else { return address }
        return "\(address.prefix(4))...\(address.suffix(4))"
    }

    private func warningText(_ warning: TransactionWarning) -> String {
        switch warning {
        case .unfundedRecipient:
            return "Recipient has 0 SOL balance (may be new/unfunded)"
        case .largeAmount:
            return "Transfer exceeds 50% of your balance"
        case .unrecognizedProgram(let programId):
            return "Unrecognized program: \(shortAddress(programId))"
        case .simulationFailed(let error):
            return "Simulation failed: \(error)"
        }
    }
}
