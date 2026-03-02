import SwiftUI
import DeadboltCore

struct AmountEntryView: View {
    @Binding var amountString: String
    let balanceLamports: UInt64
    let solPrice: Double

    var amountSOL: Double {
        Double(amountString) ?? 0
    }

    var amountUSD: Double {
        amountSOL * solPrice
    }

    var maxSOL: Double {
        let balance = Double(balanceLamports) / 1_000_000_000.0
        // Reserve enough for fees (~0.001 SOL for base + priority + tip)
        return max(0, balance - 0.001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Amount")
                .font(.headline)

            HStack {
                TextField("0.0", text: $amountString)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.title3, design: .monospaced))

                Text("SOL")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Button("Max") {
                    amountString = String(format: "%.9f", maxSOL)
                        .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
                }
                .buttonStyle(.bordered)
            }

            if solPrice > 0 && amountSOL > 0 {
                Text(DashboardViewModel.formatUSD(amountUSD))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if amountSOL > maxSOL && amountSOL > 0 {
                Text("Insufficient balance")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
