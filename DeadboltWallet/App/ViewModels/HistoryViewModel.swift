import Foundation
import SwiftUI
import DeadboltCore

/// P7-013: View model for transaction history.
/// Manages pagination, filtering, and refresh state.
@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var entries: [TransactionHistoryEntry] = []
    @Published var filteredEntries: [TransactionHistoryEntry] = []
    @Published var selectedFilter: TransactionFilter = .all
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let historyService: TransactionHistoryService
    private let walletAddress: String

    init(walletAddress: String) {
        self.walletAddress = walletAddress
        let rpcURL = AppConfig.defaultRPCURL
        let rpcClient = SolanaRPCClient(rpcURL: rpcURL)
        let heliusClient = HeliusClient(apiKey: AppConfig.defaultHeliusAPIKey)
        self.historyService = TransactionHistoryService(rpcClient: rpcClient, heliusClient: heliusClient)
    }

    // MARK: - Fetch

    func loadHistory(forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil

        do {
            entries = try await historyService.getHistory(
                for: walletAddress,
                limit: 50,
                forceRefresh: forceRefresh
            )
            applyFilter()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refresh() async {
        await loadHistory(forceRefresh: true)
    }

    // MARK: - Filtering

    func setFilter(_ filter: TransactionFilter) {
        selectedFilter = filter
        applyFilter()
    }

    private func applyFilter() {
        switch selectedFilter {
        case .all:
            filteredEntries = entries
        case .transfers:
            filteredEntries = entries.filter { $0.type == .transfer }
        case .swaps:
            filteredEntries = entries.filter { $0.type == .swap }
        case .staking:
            filteredEntries = entries.filter { $0.type == .stake }
        case .nfts:
            filteredEntries = entries.filter { $0.type == .nftTransfer }
        }
    }
}

/// Transaction filter options.
enum TransactionFilter: String, CaseIterable {
    case all = "All"
    case transfers = "Transfers"
    case swaps = "Swaps"
    case staking = "Staking"
    case nfts = "NFTs"
}
