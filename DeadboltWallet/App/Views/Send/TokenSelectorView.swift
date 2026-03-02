import SwiftUI
import DeadboltCore

/// P3-008: Token selector for send token flow.
/// Lists user's token balances with search/filter capability.
struct TokenSelectorView: View {
    let tokenBalances: [TokenBalance]
    let onSelect: (TokenBalance) -> Void

    @State private var searchText = ""

    private var filteredTokens: [TokenBalance] {
        if searchText.isEmpty {
            return tokenBalances
        }
        let query = searchText.lowercased()
        return tokenBalances.filter {
            $0.definition.name.lowercased().contains(query) ||
            $0.definition.mint.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Token")
                .font(.headline)

            TextField("Search tokens...", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if filteredTokens.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No tokens found")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filteredTokens) { token in
                            Button {
                                onSelect(token)
                            } label: {
                                tokenRow(token)
                            }
                            .buttonStyle(.plain)

                            if token.id != filteredTokens.last?.id {
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
    }

    private func tokenRow(_ token: TokenBalance) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(token.definition.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                if token.usdPrice > 0 {
                    Text(DashboardViewModel.formatUSD(token.usdPrice))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(DashboardViewModel.formatTokenAmount(token.uiAmount))
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if token.usdValue > 0 {
                    Text(DashboardViewModel.formatUSD(token.usdValue))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
