import SwiftUI
import DeadboltCore

struct TransactionPreviewView: View {
    let recipientAddress: String
    let amountSOL: Double
    let fees: TransactionFees
    let simulationStatus: SimulationStatus

    enum SimulationStatus: Equatable {
        case pending
        case success(computeUnits: UInt64)
        case failed(error: String)
        case skipped
    }

    var totalCostSOL: Double {
        amountSOL + fees.totalSOL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transaction Preview")
                .font(.headline)

            Divider()

            infoRow("Action", "Send \(formatSOL(amountSOL)) SOL")
            infoRow("To", shortAddress(recipientAddress))
            infoRow("Fee", "~\(formatSOL(Double(fees.baseFee) / 1e9)) SOL")
            if fees.priorityFee > 0 {
                infoRow("Priority", "~\(formatSOL(Double(fees.priorityFee) / 1e9)) SOL")
            }
            if fees.tipAmount > 0 {
                infoRow("Jito Tip", "\(formatSOL(Double(fees.tipAmount) / 1e9)) SOL")
            }

            Divider()

            infoRow("Balance Change", "-\(formatSOL(totalCostSOL)) SOL")

            Divider()

            simulationBadge
        }
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var simulationBadge: some View {
        HStack {
            Text("Simulation:")
                .foregroundStyle(.secondary)
            switch simulationStatus {
            case .pending:
                ProgressView()
                    .controlSize(.small)
                Text("Simulating...")
                    .foregroundStyle(.secondary)
            case .success(let cu):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Will succeed (\(cu) CU)")
            case .failed(let error):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(error)
            case .skipped:
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
                Text("Skipped")
            }
        }
        .font(.caption)
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
        DashboardViewModel.formatSOL(UInt64(sol * 1_000_000_000))
    }

    private func shortAddress(_ address: String) -> String {
        guard address.count > 8 else { return address }
        return "\(address.prefix(4))...\(address.suffix(4))"
    }
}
