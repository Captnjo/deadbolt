import Foundation

// MARK: - Solana Network

public enum SolanaNetwork: String, Codable, CaseIterable, Sendable {
    case mainnet = "mainnet"
    case devnet = "devnet"

    public var displayName: String {
        switch self {
        case .mainnet: return "Mainnet"
        case .devnet: return "Devnet"
        }
    }

    public func rpcURL(heliusAPIKey: String) -> URL {
        switch self {
        case .mainnet:
            return URL(string: "https://mainnet.helius-rpc.com/?api-key=\(heliusAPIKey)")!
        case .devnet:
            return URL(string: "https://devnet.helius-rpc.com/?api-key=\(heliusAPIKey)")!
        }
    }
}

// MARK: - API Key

public struct APIKey: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var label: String
    public let token: String

    public init(id: String = UUID().uuidString, label: String, token: String) {
        self.id = id
        self.label = label
        self.token = token
    }
}

// MARK: - P8-014: App Config Persistence

public actor AppConfig {
    // MARK: - Static Defaults (accessible synchronously from ViewModels)

    /// Helius API key: runtime override > environment variable > placeholder.
    /// Set via `AppConfig.defaultHeliusAPIKey = "..."` after loading from persisted config.
    public static var defaultHeliusAPIKey: String = {
        if let envKey = ProcessInfo.processInfo.environment["DEADBOLT_HELIUS_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return "MISSING_HELIUS_API_KEY"
    }()
    /// Jupiter API key: runtime override > environment variable > empty.
    /// Generate a free key at https://portal.jup.ag
    public static var defaultJupiterAPIKey: String = {
        if let envKey = ProcessInfo.processInfo.environment["DEADBOLT_JUPITER_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return ""
    }()
    /// DFlow API key: runtime override > environment variable > empty.
    /// Generate a key at https://pond.dflow.net/build/api-key
    public static var defaultDFlowAPIKey: String = {
        if let envKey = ProcessInfo.processInfo.environment["DEADBOLT_DFLOW_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return ""
    }()
    /// Preferred swap aggregator: "dflow" (default) or "jupiter".
    public static var defaultPreferredSwapAggregator: String = "dflow"
    public static var defaultNetwork: SolanaNetwork = .mainnet
    public static var defaultRPCURL: URL {
        defaultNetwork.rpcURL(heliusAPIKey: defaultHeliusAPIKey)
    }

    public private(set) var rpcURL: String
    public private(set) var network: SolanaNetwork
    public private(set) var activeWalletAddress: String?
    public private(set) var jitoEnabled: Bool
    public private(set) var apiTokens: [APIKey]
    public private(set) var heliusAPIKey: String?
    public private(set) var jupiterAPIKey: String?
    public private(set) var dflowAPIKey: String?
    public private(set) var preferredSwapAggregator: String
    public private(set) var guardrails: GuardrailsConfig
    public private(set) var authMode: String
    public private(set) var allowBiometricBypass: Bool
    public private(set) var walletNames: [String: String]

    private let filePath: String

    /// Initialize with a custom file path (useful for testing).
    /// Automatically loads persisted config from disk if the file exists.
    public init(filePath: String? = nil) {
        let path = filePath ?? {
            let base = DeadboltDirectories.dataDirectory
            return "\(base)/config.json"
        }()
        self.filePath = path
        // Defaults (overwritten by loadSync if config file exists)
        self.network = .mainnet
        self.rpcURL = SolanaNetwork.mainnet.rpcURL(heliusAPIKey: AppConfig.defaultHeliusAPIKey).absoluteString
        self.activeWalletAddress = nil
        self.jitoEnabled = true
        self.apiTokens = []
        self.heliusAPIKey = nil
        self.jupiterAPIKey = nil
        self.dflowAPIKey = nil
        self.preferredSwapAggregator = "dflow"
        self.guardrails = GuardrailsConfig()
        self.authMode = "system"
        self.allowBiometricBypass = true
        self.walletNames = [:]
        // Auto-load persisted config so callers never forget
        loadSync()
    }

    /// Synchronously load config from disk (called from init).
    private func loadSync() {
        guard FileManager.default.fileExists(atPath: filePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let stored = try? JSONDecoder().decode(StoredConfig.self, from: data) else {
            return
        }
        rpcURL = stored.rpcURL
        network = stored.network ?? .mainnet
        activeWalletAddress = stored.activeWalletAddress
        jitoEnabled = stored.jitoEnabled
        if let tokens = stored.apiTokens, !tokens.isEmpty {
            apiTokens = tokens
        } else if let legacy = stored.apiToken, !legacy.isEmpty {
            apiTokens = [APIKey(label: "Default", token: legacy)]
        } else {
            apiTokens = []
        }
        heliusAPIKey = stored.heliusAPIKey
        jupiterAPIKey = stored.jupiterAPIKey
        dflowAPIKey = stored.dflowAPIKey
        preferredSwapAggregator = stored.preferredSwapAggregator ?? "dflow"
        guardrails = stored.guardrails ?? GuardrailsConfig()
        authMode = stored.authMode ?? "system"
        allowBiometricBypass = stored.allowBiometricBypass ?? true
        walletNames = stored.walletNames ?? [:]
    }

    // MARK: - Persistence

    /// Load configuration from disk. If the file doesn't exist, keep defaults.
    public func load() throws {
        guard FileManager.default.fileExists(atPath: filePath) else {
            return
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let stored = try JSONDecoder().decode(StoredConfig.self, from: data)
        rpcURL = stored.rpcURL
        network = stored.network ?? .mainnet
        activeWalletAddress = stored.activeWalletAddress
        jitoEnabled = stored.jitoEnabled
        // Migrate old single apiToken → apiTokens array
        if let tokens = stored.apiTokens, !tokens.isEmpty {
            apiTokens = tokens
        } else if let legacy = stored.apiToken, !legacy.isEmpty {
            apiTokens = [APIKey(label: "Default", token: legacy)]
        } else {
            apiTokens = []
        }
        heliusAPIKey = stored.heliusAPIKey
        jupiterAPIKey = stored.jupiterAPIKey
        dflowAPIKey = stored.dflowAPIKey
        preferredSwapAggregator = stored.preferredSwapAggregator ?? "dflow"
        guardrails = stored.guardrails ?? GuardrailsConfig()
        authMode = stored.authMode ?? "system"
        allowBiometricBypass = stored.allowBiometricBypass ?? true
        walletNames = stored.walletNames ?? [:]
    }

    /// Save current configuration to disk. Creates parent directories if needed.
    public func save() throws {
        let dir = (filePath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let stored = StoredConfig(
            rpcURL: rpcURL,
            network: network,
            activeWalletAddress: activeWalletAddress,
            jitoEnabled: jitoEnabled,
            apiToken: nil,
            apiTokens: apiTokens,
            heliusAPIKey: heliusAPIKey,
            jupiterAPIKey: jupiterAPIKey,
            dflowAPIKey: dflowAPIKey,
            preferredSwapAggregator: preferredSwapAggregator,
            guardrails: guardrails,
            authMode: authMode,
            allowBiometricBypass: allowBiometricBypass,
            walletNames: walletNames
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(stored)
        try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
        // Set file permissions to owner-only (0600) — config may contain API token
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: filePath
        )
    }

    // MARK: - Update Methods

    /// The resolved Helius API key: persisted config > env var > placeholder.
    public var resolvedHeliusAPIKey: String {
        if let key = heliusAPIKey, !key.isEmpty { return key }
        return AppConfig.defaultHeliusAPIKey
    }

    /// Update the network and RPC URL together.
    public func update(network: SolanaNetwork) {
        self.network = network
        self.rpcURL = network.rpcURL(heliusAPIKey: resolvedHeliusAPIKey).absoluteString
        AppConfig.defaultNetwork = network
    }

    /// Update the Helius API key.
    public func update(heliusAPIKey: String?) {
        self.heliusAPIKey = heliusAPIKey
    }

    /// Update the Jupiter API key.
    public func update(jupiterAPIKey: String?) {
        self.jupiterAPIKey = jupiterAPIKey
    }

    /// Update the DFlow API key.
    public func update(dflowAPIKey: String?) {
        self.dflowAPIKey = dflowAPIKey
    }

    /// Update the preferred swap aggregator ("dflow" or "jupiter").
    public func update(preferredSwapAggregator: String) {
        self.preferredSwapAggregator = preferredSwapAggregator
    }

    /// Update the RPC URL. Enforces HTTPS unless targeting localhost.
    public func update(rpcURL: String) {
        // Allow http:// for localhost/127.0.0.1 (development), enforce HTTPS for everything else
        if let url = URL(string: rpcURL),
           let host = url.host,
           host != "localhost" && host != "127.0.0.1" && url.scheme == "http" {
            // Silently upgrade to HTTPS
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            self.rpcURL = components?.url?.absoluteString ?? rpcURL
        } else {
            self.rpcURL = rpcURL
        }
    }

    /// Update the active wallet address.
    public func update(activeWallet: String?) {
        self.activeWalletAddress = activeWallet
    }

    /// Update Jito enabled setting.
    public func update(jitoEnabled: Bool) {
        self.jitoEnabled = jitoEnabled
    }

    /// Generate a new API key with the given label. Appends to the array and returns it.
    @discardableResult
    public func generateAPIToken(label: String) -> APIKey {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let key = APIKey(label: label, token: "db_\(hex)")
        apiTokens.append(key)
        return key
    }

    /// Remove an API key by its id.
    public func removeAPIToken(id: String) {
        apiTokens.removeAll { $0.id == id }
    }

    /// Validate a bearer token against all stored API keys.
    /// Uses constant-time comparison on every key to prevent timing side-channel attacks.
    public func validateToken(_ token: String) -> Bool {
        guard !apiTokens.isEmpty else { return false }
        let fixedLen = 64
        let a = Array(token.utf8) + Array(repeating: UInt8(0), count: max(0, fixedLen - token.utf8.count))
        var anyMatch = false
        for key in apiTokens {
            let b = Array(key.token.utf8) + Array(repeating: UInt8(0), count: max(0, fixedLen - key.token.utf8.count))
            var result: UInt8 = 0
            for i in 0..<fixedLen {
                result |= a[i] ^ b[i]
            }
            if token.utf8.count != key.token.utf8.count {
                result |= 1
            }
            if result == 0 {
                anyMatch = true
            }
        }
        return anyMatch
    }

    /// Update guardrails config.
    public func update(guardrails: GuardrailsConfig) {
        self.guardrails = guardrails
    }

    /// Update auth mode ("system", "appPassword", "biometricOnly").
    public func update(authMode: String) {
        self.authMode = authMode
    }

    /// Update biometric bypass preference.
    public func update(allowBiometricBypass: Bool) {
        self.allowBiometricBypass = allowBiometricBypass
    }

    /// Update a custom wallet name for an address.
    public func update(walletName: String, forAddress address: String) {
        self.walletNames[address] = walletName
    }
}

// MARK: - Internal Codable Storage

private struct StoredConfig: Codable {
    let rpcURL: String
    let network: SolanaNetwork?
    let activeWalletAddress: String?
    let jitoEnabled: Bool
    let apiToken: String?        // Legacy single token (read-only for migration)
    let apiTokens: [APIKey]?     // Multi-key storage
    let heliusAPIKey: String?
    let jupiterAPIKey: String?
    let dflowAPIKey: String?
    let preferredSwapAggregator: String?
    let guardrails: GuardrailsConfig?
    let authMode: String?
    let allowBiometricBypass: Bool?
    let walletNames: [String: String]?
}
