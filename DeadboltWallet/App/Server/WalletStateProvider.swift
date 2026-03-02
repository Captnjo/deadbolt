import Foundation
import DeadboltCore

// MARK: - State Snapshots

struct WalletState: Sendable {
    let address: String?
    let source: String
    let network: String
}

struct BalanceState: Sendable {
    let solLamports: UInt64
    let solDisplay: Double
    let solUSD: Double
    let totalPortfolioUSD: Double
}

struct TokenBalanceInfo: Sendable {
    let mint: String
    let symbol: String
    let amount: Double
    let usdValue: Double
}

struct HistoryEntryInfo: Sendable {
    let signature: String
    let type: String
    let description: String
    let timestamp: String
}

// MARK: - Provider Protocol

protocol WalletStateProvider: Sendable {
    func getWalletState() async -> WalletState
    func getBalanceState() async -> BalanceState
    func getTokenBalances() async -> [TokenBalanceInfo]
    func getPrice(mint: String) async -> Double
    func getHistory(limit: Int) async -> [HistoryEntryInfo]
}

// MARK: - WalletService Adapter

/// Adapts the @MainActor WalletService for use from the server actor.
final class WalletServiceStateProvider: WalletStateProvider, @unchecked Sendable {
    private let walletService: WalletService

    init(walletService: WalletService) {
        self.walletService = walletService
    }

    func getWalletState() async -> WalletState {
        await MainActor.run {
            let wallet = walletService.activeWallet
            return WalletState(
                address: wallet?.address,
                source: wallet.map { sourceString($0.source) } ?? "none",
                network: walletService.network.rawValue
            )
        }
    }

    func getBalanceState() async -> BalanceState {
        await MainActor.run {
            BalanceState(
                solLamports: walletService.solBalance,
                solDisplay: walletService.solBalanceDisplay,
                solUSD: walletService.solUSDValue,
                totalPortfolioUSD: walletService.totalPortfolioUSD
            )
        }
    }

    func getTokenBalances() async -> [TokenBalanceInfo] {
        await MainActor.run {
            walletService.tokenBalances.map { tb in
                TokenBalanceInfo(
                    mint: tb.definition.mint,
                    symbol: tb.definition.name,
                    amount: tb.uiAmount,
                    usdValue: tb.usdValue
                )
            }
        }
    }

    func getPrice(mint: String) async -> Double {
        await MainActor.run {
            // Check cached token balances for price
            if let tb = walletService.tokenBalances.first(where: { $0.definition.mint == mint }) {
                return tb.usdPrice
            }
            // SOL price
            if mint == "So11111111111111111111111111111111111111112" {
                return walletService.solPrice
            }
            return 0
        }
    }

    func getHistory(limit: Int) async -> [HistoryEntryInfo] {
        guard let address = await MainActor.run(body: { walletService.activeWallet?.address }) else {
            return []
        }

        let rpcClient = SolanaRPCClient(rpcURL: AppConfig.defaultRPCURL)
        let heliusClient = HeliusClient(apiKey: AppConfig.defaultHeliusAPIKey)
        let historyService = TransactionHistoryService(rpcClient: rpcClient, heliusClient: heliusClient)

        do {
            let entries = try await historyService.getHistory(for: address, limit: limit)
            return entries.map { entry in
                HistoryEntryInfo(
                    signature: entry.signature,
                    type: "\(entry.type)",
                    description: entry.description,
                    timestamp: ISO8601DateFormatter().string(from: entry.timestamp)
                )
            }
        } catch {
            return []
        }
    }

    private func sourceString(_ source: WalletSource) -> String {
        switch source {
        case .keychain: return "hot"
        case .keypairFile: return "file"
        case .hardware: return "hardware"
        }
    }
}
