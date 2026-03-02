import SwiftUI
import DeadboltCore

/// P5-006: SOL amount input for staking.
/// Amount entry with max button and LST selection.
struct StakeInputView: View {
    @Binding var amountString: String
    @Binding var selectedLST: LSTOption
    let solBalance: UInt64
    let solPrice: Double

    var amountSOL: Double {
        Double(amountString) ?? 0
    }

    var maxSOL: Double {
        let balance = Double(solBalance) / 1_000_000_000.0
        return max(0, balance - 0.01) // Reserve for fees
    }

    var amountUSD: Double {
        amountSOL * solPrice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // SOL Amount
            VStack(alignment: .leading, spacing: 8) {
                Text("Stake SOL")
                    .font(.headline)

                HStack {
                    TextField("0.0", text: $amountString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.title3, design: .monospaced))

                    Text("SOL")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Button("Max") {
                        amountString = formatMax(maxSOL)
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Text("Balance: \(DashboardViewModel.formatSOL(solBalance)) SOL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if solPrice > 0 && amountSOL > 0 {
                        Text(DashboardViewModel.formatUSD(amountUSD))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if amountSOL > maxSOL && amountSOL > 0 {
                    Text("Insufficient balance")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Divider()

            // LST Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Stake Into")
                    .font(.headline)

                ForEach(LSTOption.allCases, id: \.self) { lst in
                    Button {
                        selectedLST = lst
                    } label: {
                        HStack {
                            Image(systemName: selectedLST == lst ? "circle.inset.filled" : "circle")
                                .foregroundStyle(selectedLST == lst ? .blue : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(lst.name)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                Text(lst.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(selectedLST == lst ? Color.blue.opacity(0.1) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func formatMax(_ amount: Double) -> String {
        var result = String(format: "%.9f", amount)
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }
}

/// Available LST options for staking.
enum LSTOption: String, CaseIterable {
    case jitoSOL
    case mSOL
    case bSOL
    case bonkSOL

    var name: String {
        switch self {
        case .jitoSOL: return "JitoSOL"
        case .mSOL: return "mSOL (Marinade)"
        case .bSOL: return "bSOL (BlazeStake)"
        case .bonkSOL: return "bonkSOL"
        }
    }

    var description: String {
        switch self {
        case .jitoSOL: return "Jito liquid staking with MEV rewards"
        case .mSOL: return "Marinade Finance liquid staking"
        case .bSOL: return "BlazeStake liquid staking"
        case .bonkSOL: return "Bonk liquid staking"
        }
    }

    var mint: String {
        switch self {
        case .jitoSOL: return LSTMint.jitoSOL
        case .mSOL: return LSTMint.mSOL
        case .bSOL: return LSTMint.bSOL
        case .bonkSOL: return LSTMint.bonkSOL
        }
    }
}
