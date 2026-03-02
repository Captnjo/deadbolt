import Foundation
import DeadboltCore

// MARK: - Guardrail Result

enum GuardrailResult: Sendable {
    case allowed
    case rejected(reason: String)

    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }
}

/// Evaluates agent intents against configurable safety rules.
/// Rules are loaded from AppConfig and can be updated at runtime.
actor GuardrailsEngine {
    private let config: AppConfig
    private let priceService: PriceService

    // Daily counters — persisted to UserDefaults
    private var dailyTransactionCount = 0
    private var dailyUSDSpent: Double = 0.0
    private var lastResetDate: Date = Date()

    // Per-agent cooldown tracking
    private var lastTransactionTime: [String: Date] = [:]

    // UserDefaults keys for counter persistence
    private static let txCountKey = "guardrails_daily_tx_count"
    private static let usdSpentKey = "guardrails_daily_usd_spent"
    private static let resetDateKey = "guardrails_last_reset_date"

    init(config: AppConfig, priceService: PriceService = PriceService()) {
        self.config = config
        self.priceService = priceService
        // Restore persisted counters
        loadPersistedCounters()
    }

    private func loadPersistedCounters() {
        let defaults = UserDefaults.standard
        dailyTransactionCount = defaults.integer(forKey: Self.txCountKey)
        dailyUSDSpent = defaults.double(forKey: Self.usdSpentKey)
        if let date = defaults.object(forKey: Self.resetDateKey) as? Date {
            lastResetDate = date
        }
        // Reset if day has changed
        resetDailyCountersIfNeeded()
    }

    private func persistCounters() {
        let defaults = UserDefaults.standard
        defaults.set(dailyTransactionCount, forKey: Self.txCountKey)
        defaults.set(dailyUSDSpent, forKey: Self.usdSpentKey)
        defaults.set(lastResetDate, forKey: Self.resetDateKey)
    }

    // MARK: - Evaluate Intent

    func evaluate(_ intent: IntentRequest, solPrice: Double) async -> GuardrailResult {
        // Reset daily counters if needed
        resetDailyCountersIfNeeded()

        let guardrails = await config.guardrails

        // Check cooldown
        if let cooldownResult = checkCooldown(intent: intent, guardrails: guardrails) {
            return cooldownResult
        }

        // Check per-transaction limits
        if let limitResult = await checkTransactionLimits(intent: intent, guardrails: guardrails, solPrice: solPrice) {
            return limitResult
        }

        // Check daily limits
        if let dailyResult = checkDailyLimits(intent: intent, guardrails: guardrails, solPrice: solPrice) {
            return dailyResult
        }

        // Check token whitelist
        if let tokenResult = checkTokenWhitelist(intent: intent, guardrails: guardrails) {
            return tokenResult
        }

        return .allowed
    }

    /// Call after a transaction is successfully submitted to update daily counters.
    func recordTransaction(usdValue: Double, agentId: String?) {
        dailyTransactionCount += 1
        dailyUSDSpent += usdValue
        if let agentId = agentId {
            lastTransactionTime[agentId] = Date()
        }
        persistCounters()
    }

    // MARK: - Daily Counter Reset

    private func resetDailyCountersIfNeeded() {
        let calendar = Calendar.current
        if !calendar.isDate(lastResetDate, inSameDayAs: Date()) {
            dailyTransactionCount = 0
            dailyUSDSpent = 0.0
            lastResetDate = Date()
            persistCounters()
        }
    }

    // MARK: - Cooldown Check

    /// Sanitize agentId to printable ASCII only, stripping control chars and Unicode direction overrides.
    private func sanitizeAgentId(_ raw: String?) -> String {
        guard let raw = raw else { return "unknown" }
        let sanitized = raw.unicodeScalars
            .filter { $0.value >= 0x20 && $0.value < 0x7F } // printable ASCII only
            .prefix(64) // cap length
        return sanitized.isEmpty ? "unknown" : String(sanitized)
    }

    private func checkCooldown(intent: IntentRequest, guardrails: GuardrailsConfig) -> GuardrailResult? {
        let agentId = sanitizeAgentId(intent.metadata?.agentId)
        if let lastTime = lastTransactionTime[agentId] {
            let elapsed = Date().timeIntervalSince(lastTime)
            let cooldown = Double(guardrails.cooldownSeconds)
            if elapsed < cooldown {
                let remaining = Int(ceil(cooldown - elapsed))
                return .rejected(reason: "Cooldown: wait \(remaining) more second\(remaining == 1 ? "" : "s") (agent: \(agentId))")
            }
        }
        return nil
    }

    // MARK: - Per-Transaction Limits

    private func checkTransactionLimits(
        intent: IntentRequest,
        guardrails: GuardrailsConfig,
        solPrice: Double
    ) async -> GuardrailResult? {
        let solAmount = extractSOLAmount(from: intent)

        // Max SOL per transaction (only applies to SOL-denominated intents)
        switch intent.params {
        case .sendSol, .stake:
            if solAmount > guardrails.maxSOLPerTransaction {
                return .rejected(reason: "Exceeds max SOL per transaction (\(formatLimit(guardrails.maxSOLPerTransaction)) SOL limit, attempted \(formatLimit(solAmount)) SOL)")
            }
        case .swap(let p):
            // Only check SOL limit if input is SOL
            if p.inputMint == "So11111111111111111111111111111111111111112" {
                if solAmount > guardrails.maxSOLPerTransaction {
                    return .rejected(reason: "Exceeds max SOL per transaction (\(formatLimit(guardrails.maxSOLPerTransaction)) SOL limit, attempted \(formatLimit(solAmount)) SOL)")
                }
            }
        default:
            break
        }

        // Max USD per transaction — estimate USD value for all intent types
        let usdValue = estimateUSDValue(intent: intent, solPrice: solPrice)
        if usdValue > guardrails.maxUSDPerTransaction {
            return .rejected(reason: "Exceeds max USD per transaction ($\(formatLimit(guardrails.maxUSDPerTransaction)) limit, attempted $\(formatLimit(usdValue)))")
        }

        return nil
    }

    /// Estimate USD value for any intent type.
    func estimateUSDValue(intent: IntentRequest, solPrice: Double) -> Double {
        switch intent.params {
        case .sendSol(let p):
            return (Double(p.amount) / 1_000_000_000.0) * solPrice
        case .stake(let p):
            return (Double(p.amount) / 1_000_000_000.0) * solPrice
        case .swap(let p):
            if p.inputMint == "So11111111111111111111111111111111111111112" {
                return (Double(p.amount) / 1_000_000_000.0) * solPrice
            }
            // For stablecoins, use face value
            let decimals = tokenDecimals(for: p.inputMint)
            let amount = Double(p.amount) / pow(10.0, Double(decimals))
            if isStablecoin(p.inputMint) {
                return amount
            }
            // For unknown tokens, approximate using SOL price
            return amount * solPrice
        case .sendToken(let p):
            let decimals = p.decimals ?? 9
            let amount = Double(p.amount) / pow(10.0, Double(decimals))
            if isStablecoin(p.mint) {
                return amount
            }
            // Unknown token — approximate with SOL price per unit
            return amount * solPrice
        default:
            return 0
        }
    }

    private func isStablecoin(_ mint: String) -> Bool {
        let stablecoins = [
            "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", // USDC
            "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB", // USDT
        ]
        return stablecoins.contains(mint)
    }

    // MARK: - Daily Limits

    private func checkDailyLimits(
        intent: IntentRequest,
        guardrails: GuardrailsConfig,
        solPrice: Double
    ) -> GuardrailResult? {
        // Daily transaction count
        if dailyTransactionCount >= guardrails.dailyTransactionLimit {
            return .rejected(reason: "Daily transaction limit reached (\(guardrails.dailyTransactionLimit) per day)")
        }

        // Daily USD limit
        let solAmount = extractSOLAmount(from: intent)
        let usdValue = solAmount * solPrice
        if dailyUSDSpent + usdValue > guardrails.dailyUSDLimit {
            return .rejected(reason: "Would exceed daily USD limit ($\(formatLimit(guardrails.dailyUSDLimit)) limit, $\(formatLimit(dailyUSDSpent)) already spent)")
        }

        return nil
    }

    // MARK: - Token Whitelist

    private func checkTokenWhitelist(intent: IntentRequest, guardrails: GuardrailsConfig) -> GuardrailResult? {
        guard !guardrails.whitelistedTokens.isEmpty else { return nil } // Empty = allow all

        switch intent.params {
        case .swap(let params):
            if !isTokenAllowed(params.inputMint, whitelist: guardrails.whitelistedTokens) {
                return .rejected(reason: "Token \(shortMint(params.inputMint)) not in whitelist")
            }
            if !isTokenAllowed(params.outputMint, whitelist: guardrails.whitelistedTokens) {
                return .rejected(reason: "Token \(shortMint(params.outputMint)) not in whitelist")
            }
        case .sendToken(let params):
            if !isTokenAllowed(params.mint, whitelist: guardrails.whitelistedTokens) {
                return .rejected(reason: "Token \(shortMint(params.mint)) not in whitelist")
            }
        case .stake(let params):
            if !isTokenAllowed(params.lstMint, whitelist: guardrails.whitelistedTokens) {
                return .rejected(reason: "Token \(shortMint(params.lstMint)) not in whitelist")
            }
        default:
            break
        }

        return nil
    }

    // MARK: - Program Whitelist (Post-build check)

    /// Check that all program IDs in a built transaction are whitelisted.
    func checkProgramWhitelist(programIds: [String], guardrails: GuardrailsConfig) -> GuardrailResult {
        guard !guardrails.whitelistedPrograms.isEmpty else { return .allowed }

        for programId in programIds {
            if !guardrails.whitelistedPrograms.contains(programId) {
                return .rejected(reason: "Unknown program \(shortMint(programId)) not in whitelist")
            }
        }
        return .allowed
    }

    // MARK: - Helpers

    private func extractSOLAmount(from intent: IntentRequest) -> Double {
        switch intent.params {
        case .sendSol(let p):
            return Double(p.amount) / 1_000_000_000.0
        case .stake(let p):
            return Double(p.amount) / 1_000_000_000.0
        case .swap(let p):
            // Use token decimals to correctly convert the input amount
            let decimals = tokenDecimals(for: p.inputMint)
            return Double(p.amount) / pow(10.0, Double(decimals))
        case .sendToken(let p):
            let decimals = p.decimals ?? 9
            return Double(p.amount) / pow(10.0, Double(decimals))
        default:
            return 0
        }
    }

    /// Look up decimals for well-known tokens, default to 9 for unknown.
    private func tokenDecimals(for mint: String) -> Int {
        switch mint {
        case "So11111111111111111111111111111111111111112": return 9
        case "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v": return 6  // USDC
        case "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB": return 6  // USDT
        default: return 9
        }
    }

    private func isTokenAllowed(_ mint: String, whitelist: [String]) -> Bool {
        // Check if mint is directly in whitelist
        if whitelist.contains(mint) { return true }

        // Check if a well-known symbol maps to this mint
        let symbolToMint: [String: String] = [
            "SOL": "So11111111111111111111111111111111111111112",
            "USDC": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            "USDT": "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",
            "JitoSOL": "J1toso1uCk3RLmjorhTtrVwY9HJ7X8V9yYac6Y7kGCPn",
            "mSOL": "mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So",
            "bSOL": "bSo13r4TkiE4KumL71LsHTPpL2euBYLFx6h9HP3piy1",
        ]

        for symbol in whitelist {
            if let knownMint = symbolToMint[symbol], knownMint == mint {
                return true
            }
        }

        return false
    }

    private func shortMint(_ mint: String) -> String {
        String(mint.prefix(8)) + "..."
    }

    private func formatLimit(_ value: Double) -> String {
        if value == Double(Int(value)) {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}
