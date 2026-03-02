import SwiftUI
import DeadboltCore

/// Settings view for configuring agent guardrails and API token.
struct GuardrailsSettingsView: View {
    @EnvironmentObject var agentService: AgentService
    @State private var maxSOL: Double = 10.0
    @State private var maxUSD: Double = 1000.0
    @State private var dailyTxLimit: Int = 50
    @State private var dailyUSDLimit: Double = 5000.0
    @State private var cooldownSeconds: Int = 5
    @State private var whitelistedTokens: [String] = []
    @State private var whitelistedPrograms: [String] = []
    @State private var newToken = ""
    @State private var newProgram = ""
    @State private var isLoaded = false

    var body: some View {
        Form {
            transactionLimitsSection
            dailyLimitsSection
            tokenWhitelistSection
            programWhitelistSection
        }
        .formStyle(.grouped)
        .navigationTitle("Guardrails")
        .task {
            await loadConfig()
        }
    }

    // MARK: - Transaction Limits

    private var transactionLimitsSection: some View {
        Section("Per-Transaction Limits") {
            HStack {
                Text("Max SOL")
                Spacer()
                TextField("SOL", value: $maxSOL, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .onChange(of: maxSOL) { _, _ in saveConfig() }
            }
            HStack {
                Text("Max USD")
                Spacer()
                TextField("USD", value: $maxUSD, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .onChange(of: maxUSD) { _, _ in saveConfig() }
            }
            HStack {
                Text("Cooldown (seconds)")
                Spacer()
                TextField("sec", value: $cooldownSeconds, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .onChange(of: cooldownSeconds) { _, _ in saveConfig() }
            }
        }
    }

    // MARK: - Daily Limits

    private var dailyLimitsSection: some View {
        Section("Daily Limits") {
            HStack {
                Text("Max Transactions/Day")
                Spacer()
                TextField("count", value: $dailyTxLimit, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .onChange(of: dailyTxLimit) { _, _ in saveConfig() }
            }
            HStack {
                Text("Max USD/Day")
                Spacer()
                TextField("USD", value: $dailyUSDLimit, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .onChange(of: dailyUSDLimit) { _, _ in saveConfig() }
            }
        }
    }

    // MARK: - Token Whitelist

    private var tokenWhitelistSection: some View {
        Section {
            if whitelistedTokens.isEmpty {
                Text("All tokens allowed")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(whitelistedTokens, id: \.self) { token in
                    HStack {
                        Text(token)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button {
                            whitelistedTokens.removeAll { $0 == token }
                            saveConfig()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                TextField("Token symbol or mint", text: $newToken)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let trimmed = newToken.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !whitelistedTokens.contains(trimmed) else { return }
                    whitelistedTokens.append(trimmed)
                    newToken = ""
                    saveConfig()
                }
                .disabled(newToken.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !whitelistedTokens.isEmpty {
                Button("Clear All (Allow All Tokens)") {
                    whitelistedTokens = []
                    saveConfig()
                }
                .foregroundStyle(.orange)
            }
        } header: {
            Text("Token Whitelist")
        } footer: {
            Text("Empty list = allow all tokens. Add symbols (SOL, USDC) or mint addresses.")
        }
    }

    // MARK: - Program Whitelist

    private var programWhitelistSection: some View {
        Section {
            if whitelistedPrograms.isEmpty {
                Text("All programs allowed")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(whitelistedPrograms, id: \.self) { program in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(programName(program))
                                .font(.caption.bold())
                            Text(String(program.prefix(16)) + "...")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            whitelistedPrograms.removeAll { $0 == program }
                            saveConfig()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                TextField("Program ID", text: $newProgram)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let trimmed = newProgram.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !whitelistedPrograms.contains(trimmed) else { return }
                    whitelistedPrograms.append(trimmed)
                    newProgram = ""
                    saveConfig()
                }
                .disabled(newProgram.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Button("Reset to Defaults") {
                whitelistedPrograms = GuardrailsConfig.defaultWhitelistedPrograms
                saveConfig()
            }
        } header: {
            Text("Program Whitelist")
        } footer: {
            Text("Empty list = allow all programs. Default includes System, Token, Jupiter, Sanctum, Jito.")
        }
    }

    // MARK: - Config Management

    private func loadConfig() async {
        let config = AppConfig()
        try? await config.load()
        let g = await config.guardrails
        maxSOL = g.maxSOLPerTransaction
        maxUSD = g.maxUSDPerTransaction
        dailyTxLimit = g.dailyTransactionLimit
        dailyUSDLimit = g.dailyUSDLimit
        cooldownSeconds = g.cooldownSeconds
        whitelistedTokens = g.whitelistedTokens
        whitelistedPrograms = g.whitelistedPrograms
        isLoaded = true
    }

    private func saveConfig() {
        guard isLoaded else { return }
        let guardrails = GuardrailsConfig(
            maxSOLPerTransaction: max(0, maxSOL),
            maxUSDPerTransaction: max(0, maxUSD),
            dailyTransactionLimit: max(1, dailyTxLimit),
            dailyUSDLimit: max(0, dailyUSDLimit),
            whitelistedTokens: whitelistedTokens,
            whitelistedPrograms: whitelistedPrograms,
            cooldownSeconds: max(0, cooldownSeconds)
        )
        Task {
            // Update the live config used by the running GuardrailsEngine
            if let liveConfig = agentService.config {
                await liveConfig.update(guardrails: guardrails)
                try? await liveConfig.save()
            } else {
                // Fallback: create new config (pre-server-start)
                let config = AppConfig()
                try? await config.load()
                await config.update(guardrails: guardrails)
                try? await config.save()
            }
        }
    }

    // MARK: - Program Name Lookup

    private func programName(_ id: String) -> String {
        switch id {
        case "11111111111111111111111111111111": return "System Program"
        case "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA": return "Token Program"
        case "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL": return "Associated Token"
        case "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4": return "Jupiter v6"
        case "5ocnV1qiCgaQR8Jb8xWnVbApfaygJ8tNoZfgPwsgx9kx": return "Sanctum Router"
        case "ComputeBudget111111111111111111111111111111": return "Compute Budget"
        case "T1pyyaTNZsKv2WcRAB8oVnk93mLJw2XzjtVYqCsaHqt": return "Jito Tip"
        default: return "Unknown"
        }
    }
}
