import SwiftUI
import DeadboltCore

/// P3-009: Amount entry for token sends with proper decimal handling.
struct TokenAmountEntryView: View {
    @Binding var amountString: String
    let token: TokenBalance
    let solPrice: Double

    var amountToken: Double {
        Double(amountString) ?? 0
    }

    var amountUSD: Double {
        amountToken * token.usdPrice
    }

    var maxAmount: Double {
        token.uiAmount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Amount")
                .font(.headline)

            HStack {
                TextField("0.0", text: $amountString)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.title3, design: .monospaced))

                Text(token.definition.name)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Button("Max") {
                    let maxStr = formatMaxAmount(maxAmount, decimals: token.definition.decimals)
                    amountString = maxStr
                }
                .buttonStyle(.bordered)
            }

            if token.usdPrice > 0 && amountToken > 0 {
                Text(DashboardViewModel.formatUSD(amountUSD))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if amountToken > maxAmount && amountToken > 0 {
                Text("Insufficient balance")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func formatMaxAmount(_ amount: Double, decimals: Int) -> String {
        let formatted = String(format: "%.\(decimals)f", amount)
        // Trim trailing zeros
        var result = formatted
        if result.contains(".") {
            while result.hasSuffix("0") { result.removeLast() }
            if result.hasSuffix(".") { result.removeLast() }
        }
        return result
    }
}
