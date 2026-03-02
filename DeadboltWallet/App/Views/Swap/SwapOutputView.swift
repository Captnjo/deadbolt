import SwiftUI
import DeadboltCore

/// P4-009: Output token selector for swaps.
/// Shows common tokens at top with search functionality.
struct SwapOutputView: View {
    let onSelect: (SwapOutputToken) -> Void
    let tokenBalances: [TokenBalance]

    @State private var searchText = ""

    /// Common output tokens shown at the top of the list.
    private static let commonTokens: [SwapOutputToken] = [
        SwapOutputToken(mint: LSTMint.wrappedSOL, name: "SOL", decimals: 9),
        SwapOutputToken(mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", name: "USDC", decimals: 6),
        SwapOutputToken(mint: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB", name: "USDT", decimals: 6),
        SwapOutputToken(mint: LSTMint.jitoSOL, name: "JitoSOL", decimals: 9),
    ]

    private var allTokens: [SwapOutputToken] {
        var result = Self.commonTokens

        // Add tokens from user's balances that are not already in common list
        let commonMints = Set(Self.commonTokens.map(\.mint))
        for tb in tokenBalances where !commonMints.contains(tb.definition.mint) {
            result.append(SwapOutputToken(
                mint: tb.definition.mint,
                name: tb.definition.name,
                decimals: tb.definition.decimals
            ))
        }

        return result
    }

    private var filteredTokens: [SwapOutputToken] {
        if searchText.isEmpty {
            return allTokens
        }
        let query = searchText.lowercased()
        return allTokens.filter {
            $0.name.lowercased().contains(query) ||
            $0.mint.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You Receive")
                .font(.headline)

            TextField("Search tokens...", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(filteredTokens, id: \.mint) { token in
                        Button {
                            onSelect(token)
                        } label: {
                            HStack {
                                Text(token.name)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Text(shortMint(token.mint))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if token.mint != filteredTokens.last?.mint {
                            Divider()
                        }
                    }
                }
                .padding()
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func shortMint(_ mint: String) -> String {
        guard mint.count > 8 else { return mint }
        return "\(mint.prefix(4))...\(mint.suffix(4))"
    }
}

/// Represents an output token for swaps.
struct SwapOutputToken: Equatable {
    let mint: String
    let name: String
    let decimals: Int
}
