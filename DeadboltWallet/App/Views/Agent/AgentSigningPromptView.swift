import SwiftUI
import DeadboltCore
#if os(macOS)
import HardwareWallet
#endif

/// Modal that appears when an AI agent submits an intent for approval.
struct AgentSigningPromptView: View {
    let request: AgentRequest
    @EnvironmentObject var agentService: AgentService
    @EnvironmentObject var walletService: WalletService
    @EnvironmentObject var authService: AuthService

    @State private var isProcessing = false
    @State private var statusMessage = ""
    @State private var showResult = false
    @State private var resultSignature: String?
    @State private var resultError: String?
    @State private var riskAcknowledged = false
    #if os(macOS)
    @State private var esp32Bridge: ESP32SerialBridge?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Preview content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    actionSection
                    if let changes = request.preview?.balanceChanges, !changes.isEmpty {
                        balanceChangesSection(changes)
                    }
                    if let fees = request.preview?.fees {
                        feesSection(fees)
                    }
                    if let sim = request.preview?.simulation {
                        simulationSection(sim)
                    }
                    warningsSection
                }
                .padding(20)
            }

            Divider()

            // Action buttons
            if showResult {
                resultSection
            } else {
                actionButtons
            }
        }
        .frame(width: 440, height: 520)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "cpu")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Agent Request")
                    .font(.headline)
                Spacer()
                statusBadge
            }

            if let metadata = request.intent.metadata {
                HStack {
                    if let agentId = metadata.agentId {
                        Text("from: \(agentId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if let reason = metadata.reason {
                    HStack {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                        Spacer()
                    }
                }
            }
        }
        .padding(20)
    }

    private var statusBadge: some View {
        Group {
            switch request.status {
            case .pendingApproval:
                Text("PENDING")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.15))
                    .clipShape(Capsule())
            case .signing:
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("SIGNING")
                        .font(.caption2.bold())
                        .foregroundStyle(.blue)
                }
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Action

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Action")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(request.preview?.action ?? IntentServer.describeIntent(request.intent))
                .font(.body.bold())
        }
    }

    // MARK: - Balance Changes

    private func balanceChangesSection(_ changes: [IntentBalanceChange]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Balance Changes")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                HStack {
                    Text(change.token)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(change.amount)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(change.amount.hasPrefix("+") ? .green : .red)
                }
            }
        }
    }

    // MARK: - Fees

    private func feesSection(_ fees: FeesPreview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fees")
                .font(.caption)
                .foregroundStyle(.secondary)
            feeRow("Base", lamports: fees.base)
            feeRow("Priority", lamports: fees.priority)
            feeRow("Jito Tip", lamports: fees.tip)
            Divider()
            HStack {
                Text("Total")
                    .font(.caption.bold())
                Spacer()
                Text("\(String(format: "%.6f", fees.totalSOL)) SOL")
                    .font(.system(.caption, design: .monospaced).bold())
            }
        }
    }

    private func feeRow(_ label: String, lamports: UInt64) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(String(format: "%.6f", Double(lamports) / 1_000_000_000.0)) SOL")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Simulation

    private func simulationSection(_ sim: SimulationResult) -> some View {
        HStack {
            if sim.success {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Simulation: Success")
                    .font(.caption)
                if let cu = sim.computeUnitsUsed {
                    Text("(\(cu) CU)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Simulation: Failed")
                    .font(.caption)
                if let err = sim.error {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
        }
    }

    // MARK: - Warnings

    /// Whether simulation failed on a high-value transaction (> 1 SOL).
    private var isHighRiskFailedSimulation: Bool {
        guard let sim = request.preview?.simulation, !sim.success else { return false }
        let solAmount = extractSOLAmount(from: request.intent)
        return solAmount > 1.0
    }

    private func extractSOLAmount(from intent: IntentRequest) -> Double {
        switch intent.params {
        case .sendSol(let p): return Double(p.amount) / 1_000_000_000.0
        case .swap(let p): return Double(p.amount) / 1_000_000_000.0
        case .stake(let p): return Double(p.amount) / 1_000_000_000.0
        default: return 0
        }
    }

    private var warningsSection: some View {
        Group {
            // Failed simulation red banner
            if let sim = request.preview?.simulation, !sim.success {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "xmark.shield.fill")
                            .foregroundStyle(.white)
                        Text("SIMULATION FAILED")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    if let err = sim.error {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    if isHighRiskFailedSimulation {
                        Toggle("I understand the risks", isOn: $riskAcknowledged)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .toggleStyle(.checkbox)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(.red))
            }

            let warnings = request.preview?.warnings ?? []
            if warnings.isEmpty && request.preview?.simulation?.success != false {
                HStack {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(.green)
                    Text("No warnings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(warnings, id: \.self) { warning in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text(warning)
                                .font(.caption)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button {
                    Task { await reject() }
                } label: {
                    Text("Reject")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing)

                Button {
                    // Set processing synchronously before Task to prevent double-tap
                    guard !isProcessing else { return }
                    isProcessing = true
                    Task { await approve() }
                } label: {
                    if isProcessing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Signing...")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Approve & Sign")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || (isHighRiskFailedSimulation && !riskAcknowledged))
            }

            #if os(macOS)
            if walletService.activeWallet?.source.isHardware == true {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundStyle(.blue)
                    Text("Hardware: Press BOOT button on ESP32")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            #endif
        }
        .padding(20)
    }

    // MARK: - Result

    private var resultSection: some View {
        VStack(spacing: 8) {
            if let sig = resultSignature {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Confirmed")
                        .font(.body.bold())
                }
                Text(String(sig.prefix(8)) + "..." + String(sig.suffix(8)))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            } else if let error = resultError {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Failed")
                        .font(.body.bold())
                }
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
    }

    // MARK: - Actions

    private func approve() async {
        statusMessage = "Signing..."

        await agentService.requestQueue.updateStatus(request.id, status: .signing)

        guard let wallet = walletService.activeWallet else {
            resultError = "No wallet selected"
            showResult = true
            isProcessing = false
            return
        }

        do {
            // Require auth for hot wallets (hardware wallets use physical button)
            if wallet.source != .hardware {
                guard await authService.authenticate(reason: "Approve agent transaction signing") else {
                    resultError = "Authentication required"
                    showResult = true
                    isProcessing = false
                    return
                }
            }

            // Create signer
            let signer = try await createSigner(for: wallet)
            let rpcClient = SolanaRPCClient(rpcURL: AppConfig.defaultRPCURL)
            let router = IntentRouter(rpcClient: rpcClient, walletService: walletService)

            // Process the intent
            let result = try await router.processIntent(request.intent, signer: signer)

            // Submit the transaction
            await agentService.requestQueue.updateStatus(request.id, status: .submitted)
            await agentService.requestQueue.setPreview(request.id, preview: result.preview)

            let txBuilder = TransactionBuilder(rpcClient: rpcClient)
            let signature: String

            switch result.payload {
            case .legacy(let tx):
                signature = try await txBuilder.submitViaJito(transaction: tx)
            case .versioned(let tx):
                signature = try await txBuilder.submitSwapViaJito(transaction: tx)
            case .stakeBundle(let stake, let tip):
                signature = try await txBuilder.submitStakeViaJito(stakeTransaction: stake, tipTransaction: tip)
            case .signedMessage(let sig):
                let base58Sig = Base58.encode(sig)
                await agentService.requestQueue.setConfirmed(request.id, signature: base58Sig, slot: nil)
                resultSignature = base58Sig
                showResult = true
                isProcessing = false
                return
            case .walletCreated(let address):
                let finalAddress: String
                if address == "pending_creation" {
                    // Deferred key generation — generate now after user approval
                    let keypair = try WalletGenerator.generateRandom()
                    try KeychainManager.storeSeed(keypair.seed, address: keypair.publicKey.base58)
                    finalAddress = keypair.publicKey.base58
                } else {
                    finalAddress = address
                }
                await agentService.requestQueue.setConfirmed(request.id, signature: finalAddress, slot: nil)
                resultSignature = finalAddress
                showResult = true
                isProcessing = false
                return
            }

            await agentService.requestQueue.setConfirmed(request.id, signature: signature, slot: nil)
            resultSignature = signature
            showResult = true

            // Record transaction in guardrails engine for daily counters
            if let engine = agentService.guardrailsEngine {
                let solPrice = (try? await PriceService().fetchSOLPrice()) ?? 150.0
                let usdValue = await engine.estimateUSDValue(intent: request.intent, solPrice: solPrice)
                await engine.recordTransaction(
                    usdValue: usdValue,
                    agentId: request.intent.metadata?.agentId
                )
            }
        } catch {
            await agentService.requestQueue.setFailed(request.id, error: error.localizedDescription)
            resultError = error.localizedDescription
            showResult = true
        }

        isProcessing = false
    }

    private func reject() async {
        await agentService.rejectRequest(request.id)
    }

    private func createSigner(for wallet: Wallet) async throws -> TransactionSigner {
        switch wallet.source {
        case .keychain:
            guard let seed = try? KeychainManager.retrieveSeed(address: wallet.address) else {
                throw IntentRouterError.buildFailed("Cannot load seed from Keychain")
            }
            return try SoftwareSigner(seed: seed)
        case .keypairFile(let path):
            let keypair = try KeypairReader.read(from: path)
            return try SoftwareSigner(keypair: keypair)
        case .hardware:
            #if os(macOS)
            return try await loadHardwareSigner()
            #else
            throw IntentRouterError.unsupported("Hardware wallet signing is not supported on iOS")
            #endif
        }
    }

    #if os(macOS)
    private func loadHardwareSigner() async throws -> TransactionSigner {
        let detector = ESP32Detector()
        let ports = await detector.scan()

        guard let portPath = ports.first else {
            throw IntentRouterError.buildFailed("No ESP32 hardware wallet detected. Please connect your device.")
        }

        guard let port = ORSSerialPortAdapter(path: portPath, baudRate: ESP32SerialBridge.defaultBaudRate) else {
            throw IntentRouterError.buildFailed("Failed to open serial port at \(portPath)")
        }
        let bridge = ESP32SerialBridge(port: port)
        try await bridge.connect()
        self.esp32Bridge = bridge

        return bridge
    }
    #endif
}

// MARK: - Wallet Source Helper

extension WalletSource {
    var isHardware: Bool {
        if case .hardware = self { return true }
        return false
    }
}
