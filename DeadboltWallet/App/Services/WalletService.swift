import Foundation
import SwiftUI
import DeadboltCore

@MainActor
final class WalletService: ObservableObject {
    @Published var wallets: [Wallet] = []
    @Published var activeWallet: Wallet?
    @Published var solBalance: UInt64 = 0
    @Published var solPrice: Double = 0
    @Published var tokenBalances: [TokenBalance] = []
    @Published var tokenDefinitions: [TokenDefinition] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var network: SolanaNetwork = .mainnet

    private var rpcClient: SolanaRPCClient
    private let priceService = PriceService()

    var solBalanceDisplay: Double {
        Double(solBalance) / 1_000_000_000.0
    }

    var solUSDValue: Double {
        solBalanceDisplay * solPrice
    }

    var totalPortfolioUSD: Double {
        solUSDValue + tokenBalances.reduce(0) { $0 + $1.usdValue }
    }

    init(rpcURL: URL = AppConfig.defaultRPCURL) {
        self.rpcClient = SolanaRPCClient(rpcURL: rpcURL)
    }

    // MARK: - Wallet Discovery

    func loadWallets() {
        var discovered: [Wallet] = []

        // Preserve any hardware wallets already registered (e.g. from boot detection)
        let existingHardware = wallets.filter { $0.source == .hardware }
        discovered.append(contentsOf: existingHardware)

        // Keychain-stored wallets (only if user explicitly created/imported them)
        if let addresses = try? KeychainManager.listStoredAddresses() {
            for addr in addresses {
                if let pubKey = try? SolanaPublicKey(base58: addr) {
                    discovered.append(Wallet(publicKey: pubKey, name: "Hot Wallet", source: .keychain))
                }
            }
        }

        // File-based keypairs (only from the deadbolt-specific directory, not generic solana dir)
        let keypairs = KeypairReader.discoverKeypairs()
        for kp in keypairs {
            let fileName = (kp.sourcePath ?? "unknown").split(separator: "/").last.map(String.init) ?? "unknown"
            let name = fileName.replacingOccurrences(of: ".json", with: "")
            let alreadyFound = discovered.contains { $0.address == kp.publicKey.base58 }
            if !alreadyFound {
                discovered.append(Wallet(publicKey: kp.publicKey, name: name, source: .keypairFile(path: kp.sourcePath ?? "")))
            }
        }

        self.wallets = discovered
        if activeWallet == nil {
            activeWallet = discovered.first
        }
    }

    /// Remove all hot wallets stored in Keychain.
    func clearKeychainWallets() {
        if let addresses = try? KeychainManager.listStoredAddresses() {
            for addr in addresses {
                try? KeychainManager.deleteSeed(address: addr)
            }
        }
        // Reload — will now be empty unless hardware wallet or keypair files exist
        let hadActive = activeWallet
        wallets = []
        activeWallet = nil
        solBalance = 0
        tokenBalances = []
        loadWallets()
        if activeWallet == nil && hadActive != nil {
            errorMessage = nil
        }
    }

    // MARK: - Token Definitions

    func loadTokenDefinitions() {
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let tokensPath = "\(home)/.config/solana/deadbolt/tokens.txt"
        #else
        let tokensPath = DeadboltDirectories.dataDirectory + "/tokens.txt"
        #endif

        guard let contents = try? String(contentsOfFile: tokensPath, encoding: .utf8) else {
            return
        }

        tokenDefinitions = contents
            .components(separatedBy: .newlines)
            .compactMap { TokenDefinition.parse(line: $0) }
    }

    // MARK: - Dashboard Refresh

    func refreshDashboard() async {
        guard let wallet = activeWallet else {
            errorMessage = "No wallet selected"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // Fetch balance, tokens, and SOL price in parallel
            async let balanceFetch = rpcClient.getBalance(address: wallet.address)
            async let tokensFetch = rpcClient.getTokenAccountsByOwner(address: wallet.address)
            async let priceFetch = priceService.fetchSOLPrice()

            let (balance, tokenAccounts, price) = try await (balanceFetch, tokensFetch, priceFetch)

            self.solBalance = balance
            self.solPrice = price

            // Match on-chain token accounts with known token definitions
            var balances: [TokenBalance] = []
            for account in tokenAccounts {
                let info = account.account.data.parsed.info
                guard let uiAmount = info.tokenAmount.uiAmount, uiAmount > 0 else { continue }

                let rawAmount = UInt64(info.tokenAmount.amount) ?? 0

                // Look up definition for the mint
                if let def = tokenDefinitions.first(where: { $0.mint == info.mint }) {
                    // Try to fetch live price, fall back to cached
                    let price: Double
                    if let livePrice = try? await priceService.fetchTokenPrice(mint: info.mint, decimals: def.decimals) {
                        price = livePrice
                    } else {
                        price = def.cachedPrice
                    }

                    balances.append(TokenBalance(
                        definition: def,
                        rawAmount: rawAmount,
                        uiAmount: uiAmount,
                        usdPrice: price
                    ))
                } else {
                    // Unknown token — show with mint address as name
                    let shortMint = String(info.mint.prefix(8)) + "..."
                    let def = TokenDefinition(
                        mint: info.mint,
                        name: shortMint,
                        decimals: info.tokenAmount.decimals
                    )
                    balances.append(TokenBalance(
                        definition: def,
                        rawAmount: rawAmount,
                        uiAmount: uiAmount,
                        usdPrice: 0
                    ))
                }
            }

            self.tokenBalances = balances.sorted { $0.usdValue > $1.usdValue }
            saveTokenCache()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Network Switching

    func switchNetwork(_ newNetwork: SolanaNetwork) async {
        network = newNetwork
        AppConfig.defaultNetwork = newNetwork
        let newURL = newNetwork.rpcURL(heliusAPIKey: AppConfig.defaultHeliusAPIKey)
        rpcClient = SolanaRPCClient(rpcURL: newURL)

        // Persist the choice
        let config = AppConfig()
        await config.update(network: newNetwork)
        try? await config.save()

        // Reset balances and refresh
        solBalance = 0
        tokenBalances = []
        errorMessage = nil
        await refreshDashboard()
    }

    // MARK: - Import to Keychain

    func importToKeychain(keypair: Keypair) throws {
        try KeychainManager.storeSeed(keypair.seed, address: keypair.publicKey.base58)
    }

    // MARK: - P3-013: Token Balance Cache Persistence

    private var tokenCachePath: String {
        DeadboltDirectories.dataDirectory + "/token_cache.json"
    }

    private var nftCachePath: String {
        DeadboltDirectories.dataDirectory + "/nft_cache.json"
    }

    /// Save current token balances to disk cache.
    func saveTokenCache() {
        do {
            let dir = (tokenCachePath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

            let cacheEntries = tokenBalances.map { tb in
                CachedTokenBalance(
                    mint: tb.definition.mint,
                    name: tb.definition.name,
                    decimals: tb.definition.decimals,
                    rawAmount: tb.rawAmount,
                    uiAmount: tb.uiAmount,
                    usdPrice: tb.usdPrice
                )
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(cacheEntries)
            try data.write(to: URL(fileURLWithPath: tokenCachePath))
        } catch {
            // Cache saving failure is non-critical
        }
    }

    /// Load token balances from disk cache (used on app launch before first refresh).
    func loadTokenCache() {
        guard FileManager.default.fileExists(atPath: tokenCachePath) else { return }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: tokenCachePath))
            let cached = try JSONDecoder().decode([CachedTokenBalance].self, from: data)

            tokenBalances = cached.map { entry in
                let def = TokenDefinition(
                    mint: entry.mint,
                    name: entry.name,
                    decimals: entry.decimals,
                    cachedPrice: entry.usdPrice
                )
                return TokenBalance(
                    definition: def,
                    rawAmount: entry.rawAmount,
                    uiAmount: entry.uiAmount,
                    usdPrice: entry.usdPrice
                )
            }
        } catch {
            // Cache loading failure is non-critical
        }
    }
}

/// Codable struct for persisting token balance cache.
private struct CachedTokenBalance: Codable {
    let mint: String
    let name: String
    let decimals: Int
    let rawAmount: UInt64
    let uiAmount: Double
    let usdPrice: Double
}
