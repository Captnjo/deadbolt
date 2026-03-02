import SwiftUI
import DeadboltCore

/// P4-010: Display swap quote details (Jupiter or DFlow).
/// Shows exchange rate, price impact, minimum received, and route info.
/// Auto-refreshes the quote periodically.
struct SwapQuoteView: View {
    let quote: JupiterQuote
    let inputTokenName: String
    let outputTokenName: String
    let inputDecimals: Int
    let outputDecimals: Int
    let isRefreshing: Bool
    let aggregatorName: String
    let onRefresh: () -> Void

    private var inputAmount: Double {
        (Double(quote.inAmount) ?? 0) / pow(10.0, Double(inputDecimals))
    }

    private var outputAmount: Double {
        (Double(quote.outAmount) ?? 0) / pow(10.0, Double(outputDecimals))
    }

    private var minimumReceived: Double {
        (Double(quote.otherAmountThreshold) ?? 0) / pow(10.0, Double(outputDecimals))
    }

    private var exchangeRate: Double {
        guard inputAmount > 0 else { return 0 }
        return outputAmount / inputAmount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quote")
                    .font(.headline)
                Text("via \(aggregatorName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Exchange rate
            infoRow("Rate", "1 \(inputTokenName) = \(formatAmount(exchangeRate)) \(outputTokenName)")

            // Output amount
            infoRow("You Receive", "\(formatAmount(outputAmount)) \(outputTokenName)")

            // Minimum received (accounting for slippage)
            infoRow("Min. Received", "\(formatAmount(minimumReceived)) \(outputTokenName)")

            // Price impact
            if let priceImpact = quote.priceImpactPct {
                let impactVal = Double(priceImpact) ?? 0
                let impactStr = String(format: "%.4f%%", impactVal * 100)
                HStack {
                    Text("Price Impact")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(impactStr)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(impactVal > 0.01 ? .red : .primary)
                }
            }

            // Slippage
            let slippageStr = String(format: "%.2f%%", Double(quote.slippageBps) / 100.0)
            infoRow("Slippage Tolerance", slippageStr)

            // Route
            if !quote.routePlan.isEmpty {
                Divider()
                Text("Route")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(Array(quote.routePlan.enumerated()), id: \.offset) { _, step in
                    HStack {
                        Text(step.swapInfo.label ?? "Unknown DEX")
                            .font(.caption)
                        Spacer()
                        Text("\(step.percent)%")
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
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

    private func formatAmount(_ amount: Double) -> String {
        DashboardViewModel.formatTokenAmount(amount)
    }
}

// MARK: - DFlow Quote View

/// Minimal quote display for DFlow orders.
/// DFlow returns a ready-to-sign transaction without detailed route info.
struct DFlowQuoteView: View {
    let inputTokenName: String
    let outputTokenName: String
    let inputAmount: String
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quote")
                    .font(.headline)
                Text("via DFlow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            HStack {
                Text("Swap")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(inputAmount) \(inputTokenName) -> \(outputTokenName)")
                    .fontWeight(.medium)
                    .monospacedDigit()
            }

            HStack {
                Text("Slippage Tolerance")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("0.50%")
                    .fontWeight(.medium)
                    .monospacedDigit()
            }

            Text("DFlow provides MEV-protected execution. Exact output determined at execution.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
