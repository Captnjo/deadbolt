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
    private var walletNames: [String: String] = [:]

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
        // Load custom wallet names from persisted config (sync file read)
        loadWalletNamesFromDisk()

        var discovered: [Wallet] = []

        // Preserve any hardware wallets already registered (e.g. from boot detection)
        let existingHardware = wallets.filter { $0.source == .hardware }
        discovered.append(contentsOf: existingHardware)

        // Keychain-stored wallets (only if user explicitly created/imported them)
        if let addresses = try? KeychainManager.listStoredAddresses() {
            for (index, addr) in addresses.enumerated() {
                if let pubKey = try? SolanaPublicKey(base58: addr) {
                    let number = index + 1
                    let name = addresses.count == 1 ? "Hot Wallet" : "Hot Wallet #\(number)"
                    discovered.append(Wallet(publicKey: pubKey, name: name, source: .keychain))
                }
            }
        }

        // File-based keypairs (only from the deadbolt-specific directory, not generic solana dir)
        let ignored = ignoredKeypairAddresses
        let keypairs = KeypairReader.discoverKeypairs()
        for kp in keypairs {
            let address = kp.publicKey.base58
            guard !ignored.contains(address) else { continue }
            let fileName = (kp.sourcePath ?? "unknown").split(separator: "/").last.map(String.init) ?? "unknown"
            let name = fileName.replacingOccurrences(of: ".json", with: "")
            let alreadyFound = discovered.contains { $0.address == address }
            if !alreadyFound {
                discovered.append(Wallet(publicKey: kp.publicKey, name: name, source: .keypairFile(path: kp.sourcePath ?? "")))
            }
        }

        // Apply custom wallet names (overrides default "Hot Wallet" / filename names)
        for i in discovered.indices {
            if let customName = walletNames[discovered[i].address] {
                discovered[i].name = customName
            }
        }

        self.wallets = discovered
        if activeWallet == nil {
            activeWallet = discovered.first
        }

        // Auto-sync wallets to the address book so they appear as recipients
        syncWalletsToAddressBook(discovered)
    }

    /// Add any wallets not already in the address book, using their display name as the tag.
    private func syncWalletsToAddressBook(_ wallets: [Wallet]) {
        Task {
            let addressBook = AddressBook()
            try? await addressBook.load()
            let existing = await addressBook.entries()
            let existingAddresses = Set(existing.map(\.address))

            var changed = false
            for wallet in wallets {
                guard !existingAddresses.contains(wallet.address) else { continue }
                try? await addressBook.add(address: wallet.address, tag: wallet.name)
                changed = true
            }
            if changed {
                try? await addressBook.save()
            }
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
        } catch is CancellationError {
            // Task was cancelled (e.g. view reloaded) — not a real error
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Network request cancelled during view transition — not a real error
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

    // MARK: - Helius API Key

    func updateHeliusAPIKey(_ key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        AppConfig.defaultHeliusAPIKey = trimmed

        // Rebuild RPC client with the new key
        let newURL = network.rpcURL(heliusAPIKey: trimmed)
        rpcClient = SolanaRPCClient(rpcURL: newURL)

        // Persist
        let config = AppConfig()
        try? await config.load()
        await config.update(heliusAPIKey: trimmed)
        try? await config.save()

        // Refresh dashboard with new key
        solBalance = 0
        tokenBalances = []
        errorMessage = nil
        await refreshDashboard()
    }

    // MARK: - Jupiter API Key

    func updateJupiterAPIKey(_ key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        AppConfig.defaultJupiterAPIKey = trimmed

        // Persist
        let config = AppConfig()
        try? await config.load()
        await config.update(jupiterAPIKey: trimmed)
        try? await config.save()
    }

    // MARK: - DFlow API Key

    func updateDFlowAPIKey(_ key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        AppConfig.defaultDFlowAPIKey = trimmed

        // Persist
        let config = AppConfig()
        try? await config.load()
        await config.update(dflowAPIKey: trimmed)
        try? await config.save()
    }

    // MARK: - Preferred Swap Aggregator

    func updatePreferredSwapAggregator(_ aggregator: String) async {
        AppConfig.defaultPreferredSwapAggregator = aggregator

        // Persist
        let config = AppConfig()
        try? await config.load()
        await config.update(preferredSwapAggregator: aggregator)
        try? await config.save()
    }

    // MARK: - Import to Keychain

    func importToKeychain(keypair: Keypair) throws {
        try KeychainManager.storeSeed(keypair.seed, address: keypair.publicKey.base58)
    }

    // MARK: - Remove Wallet

    /// Remove a wallet. Keychain wallets have their seed deleted. Keypair-file wallets are just
    /// de-listed (file is NOT deleted — too dangerous). Hardware wallets are de-registered.
    func removeWallet(_ wallet: Wallet) {
        switch wallet.source {
        case .keychain:
            try? KeychainManager.deleteSeed(address: wallet.address)
        case .keypairFile:
            // Don't delete keypair files — just stop listing them.
            // We track ignored addresses so discoverKeypairs results are filtered out.
            var ignored = ignoredKeypairAddresses
            ignored.insert(wallet.address)
            UserDefaults.standard.set(Array(ignored), forKey: Self.ignoredKeypairsKey)
        case .hardware:
            break // Just remove from the in-memory list
        }

        wallets.removeAll { $0.id == wallet.id }
        if activeWallet?.id == wallet.id {
            activeWallet = wallets.first
        }
    }

    // MARK: - Rename Wallet

    func renameWallet(_ wallet: Wallet, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        walletNames[wallet.address] = trimmed

        // Update the wallet in the array
        if let idx = wallets.firstIndex(where: { $0.id == wallet.id }) {
            wallets[idx].name = trimmed
        }
        // Update activeWallet if it's the same
        if activeWallet?.id == wallet.id {
            activeWallet?.name = trimmed
        }

        // Persist to AppConfig
        Task {
            let config = AppConfig()
            try? await config.load()
            await config.update(walletName: trimmed, forAddress: wallet.address)
            try? await config.save()
        }
    }

    /// Read persisted config synchronously (avoids actor isolation).
    /// Bootstraps walletNames and Helius API key before first RPC call.
    private func loadWalletNamesFromDisk() {
        let configPath = DeadboltDirectories.dataDirectory + "/config.json"
        guard FileManager.default.fileExists(atPath: configPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let names = json["walletNames"] as? [String: String] {
            walletNames = names
        }
        // Bootstrap network from config (must come before API key so RPC URL is correct)
        if let networkStr = json["network"] as? String,
           let savedNetwork = SolanaNetwork(rawValue: networkStr) {
            network = savedNetwork
            AppConfig.defaultNetwork = savedNetwork
        }
        // Bootstrap API keys from config (persisted config always wins over env vars)
        if let key = json["heliusAPIKey"] as? String, !key.isEmpty {
            AppConfig.defaultHeliusAPIKey = key
        } else if let rpcURL = json["rpcURL"] as? String,
                  let components = URLComponents(string: rpcURL),
                  let apiKey = components.queryItems?.first(where: { $0.name == "api-key" })?.value,
                  !apiKey.isEmpty {
            // Fallback: extract Helius key from persisted rpcURL
            AppConfig.defaultHeliusAPIKey = apiKey
        }
        // Always rebuild RPC client with the resolved network + Helius key
        rpcClient = SolanaRPCClient(rpcURL: network.rpcURL(heliusAPIKey: AppConfig.defaultHeliusAPIKey))
        if let key = json["jupiterAPIKey"] as? String, !key.isEmpty {
            AppConfig.defaultJupiterAPIKey = key
        }
        if let key = json["dflowAPIKey"] as? String, !key.isEmpty {
            AppConfig.defaultDFlowAPIKey = key
        }
        if let agg = json["preferredSwapAggregator"] as? String, !agg.isEmpty {
            AppConfig.defaultPreferredSwapAggregator = agg
        }
    }

    private static let ignoredKeypairsKey = "deadbolt_ignored_keypairs"

    private var ignoredKeypairAddresses: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.ignoredKeypairsKey) ?? [])
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
