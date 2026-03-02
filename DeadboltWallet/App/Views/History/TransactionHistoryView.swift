import SwiftUI
import DeadboltCore

/// P7-009: Transaction history list view with filters.
/// Shows paginated list of transactions with type icon, description, timestamp, and amount.
struct TransactionHistoryView: View {
    @EnvironmentObject var walletService: WalletService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: HistoryViewModel

    @State private var selectedEntry: TransactionHistoryEntry?

    init(walletAddress: String) {
        _viewModel = StateObject(wrappedValue: HistoryViewModel(walletAddress: walletAddress))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Transaction History")
                    .font(.headline)

                Spacer()

                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
            .padding()

            Divider()

            // P7-011: Filter bar
            filterBar

            Divider()

            // Transaction list
            if viewModel.isLoading && viewModel.entries.isEmpty {
                Spacer()
                ProgressView("Loading history...")
                Spacer()
            } else if viewModel.filteredEntries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(viewModel.entries.isEmpty ? "No transactions yet" : "No transactions match filter")
                        .foregroundStyle(.secondary)
                    if viewModel.entries.isEmpty {
                        Text("Transactions will appear here once you send, receive, or swap.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.filteredEntries, id: \.signature) { entry in
                            Button {
                                selectedEntry = entry
                            } label: {
                                transactionRow(entry)
                            }
                            .buttonStyle(.plain)

                            Divider()
                        }
                    }
                    .padding(.horizontal)
                }
            }

            if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error)
                        .font(.caption)
                }
                .foregroundStyle(.red)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 500, minHeight: 500)
        .task {
            await viewModel.loadHistory()
        }
        .sheet(item: $selectedEntry) { entry in
            TransactionDetailView(entry: entry)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(TransactionFilter.allCases, id: \.self) { filter in
                Button {
                    viewModel.setFilter(filter)
                } label: {
                    Text(filter.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(viewModel.selectedFilter == filter ? Color.accentColor : Color.gray.opacity(0.2))
                        .foregroundStyle(viewModel.selectedFilter == filter ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Transaction Row

    private func transactionRow(_ entry: TransactionHistoryEntry) -> some View {
        HStack(spacing: 12) {
            // Type icon
            typeIcon(entry.type)

            // Description + timestamp
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.description)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(formatTimestamp(entry.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Amount
            if let amount = entry.amount {
                Text(amount)
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func typeIcon(_ type: TransactionType) -> some View {
        let (icon, color) = iconForType(type)
        return Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(color)
            .frame(width: 28)
    }

    private func iconForType(_ type: TransactionType) -> (String, Color) {
        switch type {
        case .transfer: return ("arrow.up.arrow.down", .blue)
        case .swap: return ("arrow.triangle.2.circlepath", .orange)
        case .stake: return ("lock.fill", .purple)
        case .nftTransfer: return ("photo", .green)
        case .unknown: return ("questionmark.circle", .secondary)
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// Make TransactionHistoryEntry identifiable for sheet binding
extension TransactionHistoryEntry: @retroactive Identifiable {
    public var id: String { signature }
}
