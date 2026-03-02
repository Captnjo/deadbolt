import SwiftUI
import DeadboltCore

/// P7-010: Transaction detail view.
/// Shows full transfer breakdown, account changes, fee info, and explorer link.
struct TransactionDetailView: View {
    let entry: TransactionHistoryEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Transaction Details")
                    .font(.headline)

                Spacer()

                Color.clear.frame(width: 24)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Overview
                    overviewSection

                    // Native transfers
                    if !entry.nativeTransfers.isEmpty {
                        nativeTransfersSection
                    }

                    // Token transfers
                    if !entry.tokenTransfers.isEmpty {
                        tokenTransfersSection
                    }

                    // Explorer link
                    explorerSection
                }
                .padding()
            }
        }
        .frame(minWidth: 450, minHeight: 400)
    }

    // MARK: - Overview

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(.headline)

            infoRow("Type", typeLabel(entry.type))
            infoRow("Description", entry.description)
            infoRow("Date", formatDate(entry.timestamp))

            if let amount = entry.amount {
                infoRow("Amount", amount)
            }

            // Signature
            VStack(alignment: .leading, spacing: 4) {
                Text("Signature")
                    .foregroundStyle(.secondary)
                HStack {
                    Text(entry.signature)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)

                    Button {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.signature, forType: .string)
                        #else
                        UIPasteboard.general.string = entry.signature
                        #endif
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Native Transfers

    private var nativeTransfersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOL Transfers")
                .font(.headline)

            ForEach(Array(entry.nativeTransfers.enumerated()), id: \.offset) { _, transfer in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From: \(shortAddress(transfer.fromUserAccount))")
                            .font(.caption)
                        Text("To: \(shortAddress(transfer.toUserAccount))")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)

                    Spacer()

                    let solAmount = Double(transfer.amount) / 1_000_000_000.0
                    Text("\(DashboardViewModel.formatTokenAmount(solAmount)) SOL")
                        .monospacedDigit()
                        .fontWeight(.medium)
                }
                .padding(.vertical, 4)

                if transfer != entry.nativeTransfers.last {
                    Divider()
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Token Transfers

    private var tokenTransfersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token Transfers")
                .font(.headline)

            ForEach(Array(entry.tokenTransfers.enumerated()), id: \.offset) { _, transfer in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if let from = transfer.fromUserAccount {
                            Text("From: \(shortAddress(from))")
                                .font(.caption)
                        }
                        if let to = transfer.toUserAccount {
                            Text("To: \(shortAddress(to))")
                                .font(.caption)
                        }
                        Text("Mint: \(shortAddress(transfer.mint))")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)

                    Spacer()

                    Text(DashboardViewModel.formatTokenAmount(transfer.tokenAmount))
                        .monospacedDigit()
                        .fontWeight(.medium)
                }
                .padding(.vertical, 4)

                if transfer != entry.tokenTransfers.last {
                    Divider()
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Explorer

    private var explorerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                let url = URL(string: "https://solscan.io/tx/\(entry.signature)")!
                NSWorkspace.shared.open(url)
            } label: {
                HStack {
                    Image(systemName: "globe")
                    Text("View on Solscan")
                }
            }
            .buttonStyle(.bordered)

            Button {
                let url = URL(string: "https://explorer.solana.com/tx/\(entry.signature)")!
                NSWorkspace.shared.open(url)
            } label: {
                HStack {
                    Image(systemName: "globe")
                    Text("View on Solana Explorer")
                }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
            Spacer()
        }
    }

    private func typeLabel(_ type: TransactionType) -> String {
        switch type {
        case .transfer: return "Transfer"
        case .swap: return "Swap"
        case .stake: return "Stake"
        case .nftTransfer: return "NFT Transfer"
        case .unknown: return "Unknown"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func shortAddress(_ address: String) -> String {
        guard address.count > 8 else { return address }
        return "\(address.prefix(4))...\(address.suffix(4))"
    }
}
