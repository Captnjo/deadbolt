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

// MARK: - P8-014: App Config Persistence

public actor AppConfig {
    // MARK: - Static Defaults (accessible synchronously from ViewModels)

    /// Helius API key loaded from environment variable DEADBOLT_HELIUS_API_KEY,
    /// or from the persisted config. Never hardcoded in source.
    public static var defaultHeliusAPIKey: String {
        if let envKey = ProcessInfo.processInfo.environment["DEADBOLT_HELIUS_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        #if DEBUG
        // In debug builds, fall back to a placeholder that will produce clear errors
        return "MISSING_HELIUS_API_KEY"
        #else
        return "MISSING_HELIUS_API_KEY"
        #endif
    }
    public static var defaultNetwork: SolanaNetwork = .mainnet
    public static var defaultRPCURL: URL {
        defaultNetwork.rpcURL(heliusAPIKey: defaultHeliusAPIKey)
    }

    public private(set) var rpcURL: String
    public private(set) var network: SolanaNetwork
    public private(set) var activeWalletAddress: String?
    public private(set) var jitoEnabled: Bool
    public private(set) var apiToken: String?
    public private(set) var heliusAPIKey: String?
    public private(set) var guardrails: GuardrailsConfig

    private let filePath: String

    /// Initialize with a custom file path (useful for testing).
    /// Defaults are: Helius mainnet RPC, no active wallet, Jito enabled.
    public init(filePath: String? = nil) {
        let path = filePath ?? {
            let base = DeadboltDirectories.dataDirectory
            return "\(base)/config.json"
        }()
        self.filePath = path
        self.network = .mainnet
        self.rpcURL = SolanaNetwork.mainnet.rpcURL(heliusAPIKey: AppConfig.defaultHeliusAPIKey).absoluteString
        self.activeWalletAddress = nil
        self.jitoEnabled = true
        self.apiToken = nil
        self.heliusAPIKey = nil
        self.guardrails = GuardrailsConfig()
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
        apiToken = stored.apiToken
        heliusAPIKey = stored.heliusAPIKey
        guardrails = stored.guardrails ?? GuardrailsConfig()
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
            apiToken: apiToken,
            heliusAPIKey: heliusAPIKey,
            guardrails: guardrails
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

    /// Update API token.
    public func update(apiToken: String?) {
        self.apiToken = apiToken
    }

    /// Generate a new API token (db_ prefix + 32 hex chars).
    public func generateAPIToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let token = "db_\(hex)"
        self.apiToken = token
        return token
    }

    /// Validate a bearer token against the stored API token.
    /// Uses constant-time HMAC-based equality to prevent timing side-channel attacks
    /// (including length oracle: tokens are always "db_" + 32 hex chars = 35 bytes).
    public func validateToken(_ token: String) -> Bool {
        guard let stored = apiToken, !stored.isEmpty else { return false }
        // All valid tokens are exactly 35 bytes ("db_" + 32 hex chars).
        // Pad both to a fixed length to eliminate length oracle.
        let fixedLen = 64
        let a = Array(token.utf8) + Array(repeating: UInt8(0), count: max(0, fixedLen - token.utf8.count))
        let b = Array(stored.utf8) + Array(repeating: UInt8(0), count: max(0, fixedLen - stored.utf8.count))

        // Length mismatch is still a rejection but we do it after constant-time XOR
        var result: UInt8 = 0
        for i in 0..<fixedLen {
            result |= a[i] ^ b[i]
        }
        // Also reject if input length doesn't match stored length
        if token.utf8.count != stored.utf8.count {
            result |= 1
        }
        return result == 0
    }

    /// Update guardrails config.
    public func update(guardrails: GuardrailsConfig) {
        self.guardrails = guardrails
    }
}

// MARK: - Internal Codable Storage

private struct StoredConfig: Codable {
    let rpcURL: String
    let network: SolanaNetwork?
    let activeWalletAddress: String?
    let jitoEnabled: Bool
    let apiToken: String?
    let heliusAPIKey: String?
    let guardrails: GuardrailsConfig?
}
