import SwiftUI
import DeadboltCore

/// P4-008: Input token selection and amount entry for swaps.
struct SwapInputView: View {
    @Binding var selectedToken: SwapToken?
    @Binding var amountString: String
    let solBalance: UInt64
    let tokenBalances: [TokenBalance]
    let solPrice: Double

    @State private var showingTokenPicker = false

    var amountValue: Double {
        Double(amountString) ?? 0
    }

    var maxAmount: Double {
        guard let token = selectedToken else { return 0 }
        switch token {
        case .sol:
            let balance = Double(solBalance) / 1_000_000_000.0
            return max(0, balance - 0.01) // Reserve for fees
        case .token(let tb):
            return tb.uiAmount
        }
    }

    var amountUSD: Double {
        guard let token = selectedToken else { return 0 }
        switch token {
        case .sol:
            return amountValue * solPrice
        case .token(let tb):
            return amountValue * tb.usdPrice
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You Pay")
                .font(.headline)

            // Token selector button
            Button {
                showingTokenPicker = true
            } label: {
                HStack {
                    if let token = selectedToken {
                        Text(token.name)
                            .fontWeight(.medium)
                    } else {
                        Text("Select token")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Amount entry
            HStack {
                TextField("0.0", text: $amountString)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.title3, design: .monospaced))

                if selectedToken != nil {
                    Button("Max") {
                        amountString = formatMax(maxAmount)
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Balance display
            if let token = selectedToken {
                HStack {
                    Text("Balance: \(formatBalance(token))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if amountUSD > 0 {
                        Text(DashboardViewModel.formatUSD(amountUSD))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if amountValue > maxAmount && amountValue > 0 {
                Text("Insufficient balance")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .popover(isPresented: $showingTokenPicker) {
            swapTokenPicker
                .frame(width: 300, height: 400)
        }
    }

    private var swapTokenPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Input Token")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            ScrollView {
                VStack(spacing: 0) {
                    // SOL option
                    Button {
                        selectedToken = .sol
                        showingTokenPicker = false
                    } label: {
                        HStack {
                            Text("SOL")
                                .fontWeight(.medium)
                            Spacer()
                            Text(DashboardViewModel.formatSOL(solBalance))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()

                    // Token options
                    ForEach(tokenBalances) { token in
                        Button {
                            selectedToken = .token(token)
                            showingTokenPicker = false
                        } label: {
                            HStack {
                                Text(token.definition.name)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(DashboardViewModel.formatTokenAmount(token.uiAmount))
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if token.id != tokenBalances.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func formatBalance(_ token: SwapToken) -> String {
        switch token {
        case .sol:
            return DashboardViewModel.formatSOL(solBalance) + " SOL"
        case .token(let tb):
            return DashboardViewModel.formatTokenAmount(tb.uiAmount) + " " + tb.definition.name
        }
    }

    private func formatMax(_ amount: Double) -> String {
        var result = String(format: "%.9f", amount)
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }
}

/// Represents a token that can be swapped (SOL or SPL token).
enum SwapToken: Equatable {
    case sol
    case token(TokenBalance)

    var name: String {
        switch self {
        case .sol: return "SOL"
        case .token(let tb): return tb.definition.name
        }
    }

    var mint: String {
        switch self {
        case .sol: return LSTMint.wrappedSOL
        case .token(let tb): return tb.definition.mint
        }
    }

    var decimals: Int {
        switch self {
        case .sol: return 9
        case .token(let tb): return tb.definition.decimals
        }
    }

    static func == (lhs: SwapToken, rhs: SwapToken) -> Bool {
        lhs.mint == rhs.mint
    }
}
