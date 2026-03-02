import SwiftUI
import DeadboltCore

struct TokenRowView: View {
    let token: TokenBalance

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(token.definition.name)
                    .font(.body)
                    .fontWeight(.medium)
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
                if token.usdValue > 0 {
                    Text(DashboardViewModel.formatUSD(token.usdValue))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
