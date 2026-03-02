import SwiftUI
import DeadboltCore

/// P5-007: Display Sanctum staking quote.
/// Shows LST name, expected amount, exchange rate, and fees.
struct StakeQuoteView: View {
    let quote: SanctumQuote
    let lstName: String
    let solAmount: Double

    private var inAmount: Double {
        (Double(quote.inAmount) ?? 0) / 1_000_000_000.0
    }

    private var outAmount: Double {
        // LSTs typically have 9 decimals
        (Double(quote.outAmount) ?? 0) / 1_000_000_000.0
    }

    private var feeAmount: Double {
        (Double(quote.feeAmount) ?? 0) / 1_000_000_000.0
    }

    private var exchangeRate: Double {
        guard inAmount > 0 else { return 0 }
        return outAmount / inAmount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Staking Quote")
                .font(.headline)

            Divider()

            infoRow("You Stake", "\(DashboardViewModel.formatTokenAmount(solAmount)) SOL")
            infoRow("You Receive", "~\(DashboardViewModel.formatTokenAmount(outAmount)) \(lstName)")
            infoRow("Exchange Rate", "1 SOL = \(DashboardViewModel.formatTokenAmount(exchangeRate)) \(lstName)")

            if feeAmount > 0 {
                infoRow("Fee", "\(DashboardViewModel.formatTokenAmount(feeAmount)) SOL")
            }

            if let feePctVal = Double(quote.feePct), feePctVal > 0 {
                infoRow("Fee %", String(format: "%.3f%%", feePctVal * 100))
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
}
