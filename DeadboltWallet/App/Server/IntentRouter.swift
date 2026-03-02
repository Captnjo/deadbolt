import Foundation
import DeadboltCore

/// Result of processing an intent through the router.
struct IntentRouterResult: Sendable {
    enum TransactionPayload: Sendable {
        case legacy(Transaction)
        case versioned(VersionedTransaction)
        case stakeBundle(stake: VersionedTransaction, tip: Transaction)
        case signedMessage(signature: Data)
        case walletCreated(address: String)
    }

    let payload: TransactionPayload
    let preview: IntentPreview
    let fees: TransactionFees
}

/// Maps agent intents to TransactionBuilder calls and generates previews.
actor IntentRouter {
    private let rpcClient: SolanaRPCClient
    private let txBuilder: TransactionBuilder
    private let jupiterClient: JupiterClient
    private let walletService: WalletService

    init(rpcClient: SolanaRPCClient, walletService: WalletService) {
        self.rpcClient = rpcClient
        self.txBuilder = TransactionBuilder(rpcClient: rpcClient)
        self.jupiterClient = JupiterClient()
        self.walletService = walletService
    }

    // MARK: - Process Intent

    func processIntent(
        _ request: IntentRequest,
        signer: TransactionSigner
    ) async throws -> IntentRouterResult {
        switch request.params {
        case .sendSol(let params):
            return try await handleSendSOL(params, signer: signer)
        case .sendToken(let params):
            return try await handleSendToken(params, signer: signer)
        case .swap(let params):
            return try await handleSwap(params, signer: signer)
        case .stake(let params):
            return try await handleStake(params, signer: signer)
        case .signMessage(let params):
            return try await handleSignMessage(params, signer: signer)
        case .createWallet:
            return try await handleCreateWallet(request)
        case .batch(let params):
            return try await handleBatch(params, signer: signer)
        }
    }

    // MARK: - Batch Intent

    func processBatch(
        _ params: BatchParams,
        signer: TransactionSigner
    ) async throws -> [IntentRouterResult] {
        var results: [IntentRouterResult] = []
        for intent in params.intents {
            let result = try await processIntent(intent, signer: signer)
            results.append(result)
        }
        return results
    }

    // MARK: - Send SOL

    private func handleSendSOL(
        _ params: SendSOLParams,
        signer: TransactionSigner
    ) async throws -> IntentRouterResult {
        let recipient = try SolanaPublicKey(base58: params.recipient)

        let (transaction, fees) = try await txBuilder.buildSendSOL(
            from: signer,
            to: recipient,
            lamports: params.amount
        )

        let sol = Double(params.amount) / 1_000_000_000.0
        let shortRecipient = String(params.recipient.prefix(8)) + "..."

        // Simulate
        let simResult = await simulateTransaction(transaction)

        let preview = IntentPreview(
            action: "Send \(formatAmount(sol)) SOL to \(shortRecipient)",
            fees: FeesPreview(base: fees.baseFee, priority: fees.priorityFee, tip: fees.tipAmount),
            warnings: buildWarnings(solAmount: sol),
            simulation: simResult,
            balanceChanges: [
                IntentBalanceChange(token: "SOL", amount: "-\(formatAmount(sol + fees.totalSOL))")
            ]
        )

        return IntentRouterResult(
            payload: .legacy(transaction),
            preview: preview,
            fees: fees
        )
    }

    // MARK: - Send Token

    private func handleSendToken(
        _ params: SendTokenParams,
        signer: TransactionSigner
    ) async throws -> IntentRouterResult {
        let recipient = try SolanaPublicKey(base58: params.recipient)
        let mint = try SolanaPublicKey(base58: params.mint)
        let decimals = UInt8(params.decimals ?? 9)

        let (transaction, fees) = try await txBuilder.buildSendToken(
            from: signer,
            to: recipient,
            mint: mint,
            amount: params.amount,
            decimals: decimals
        )

        let tokenName = await lookupTokenName(params.mint)
        let uiAmount = Double(params.amount) / pow(10.0, Double(decimals))
        let shortRecipient = String(params.recipient.prefix(8)) + "..."

        let simResult = await simulateTransaction(transaction)

        let preview = IntentPreview(
            action: "Send \(formatAmount(uiAmount)) \(tokenName) to \(shortRecipient)",
            fees: FeesPreview(base: fees.baseFee, priority: fees.priorityFee, tip: fees.tipAmount),
            warnings: [],
            simulation: simResult,
            balanceChanges: [
                IntentBalanceChange(token: tokenName, amount: "-\(formatAmount(uiAmount))"),
                IntentBalanceChange(token: "SOL", amount: "-\(formatAmount(fees.totalSOL))")
            ]
        )

        return IntentRouterResult(
            payload: .legacy(transaction),
            preview: preview,
            fees: fees
        )
    }

    // MARK: - Swap

    private func handleSwap(
        _ params: SwapParams,
        signer: TransactionSigner
    ) async throws -> IntentRouterResult {
        // Fetch Jupiter quote
        let quote = try await jupiterClient.getQuote(
            inputMint: params.inputMint,
            outputMint: params.outputMint,
            amount: params.amount,
            slippageBps: params.slippageBps ?? 50
        )

        let (transaction, fees) = try await txBuilder.buildSwap(
            quote: quote,
            userPublicKey: signer.publicKey.base58,
            signer: signer
        )

        let inputName = await lookupTokenName(params.inputMint)
        let outputName = await lookupTokenName(params.outputMint)
        let inputDecimals = await lookupDecimals(params.inputMint)
        let outputDecimals = await lookupDecimals(params.outputMint)
        let inputAmount = Double(params.amount) / pow(10.0, Double(inputDecimals))
        let outAmountRaw = UInt64(quote.outAmount) ?? 0
        let outputAmount = Double(outAmountRaw) / pow(10.0, Double(outputDecimals))

        let preview = IntentPreview(
            action: "Swap \(formatAmount(inputAmount)) \(inputName) → ~\(formatAmount(outputAmount)) \(outputName)",
            fees: FeesPreview(base: fees.baseFee, priority: fees.priorityFee, tip: fees.tipAmount),
            warnings: buildSwapWarnings(quote: quote),
            simulation: nil, // Versioned transactions simulate differently
            balanceChanges: [
                IntentBalanceChange(token: inputName, amount: "-\(formatAmount(inputAmount))"),
                IntentBalanceChange(token: outputName, amount: "+\(formatAmount(outputAmount))"),
                IntentBalanceChange(token: "SOL", amount: "-\(formatAmount(fees.totalSOL))")
            ]
        )

        return IntentRouterResult(
            payload: .versioned(transaction),
            preview: preview,
            fees: fees
        )
    }

    // MARK: - Stake

    private func handleStake(
        _ params: StakeParams,
        signer: TransactionSigner
    ) async throws -> IntentRouterResult {
        let (stakeTx, tipTx, fees) = try await txBuilder.buildStake(
            signer: signer,
            outputLstMint: params.lstMint,
            amount: params.amount
        )

        let sol = Double(params.amount) / 1_000_000_000.0
        let lstName = await lookupTokenName(params.lstMint)

        let preview = IntentPreview(
            action: "Stake \(formatAmount(sol)) SOL → \(lstName)",
            fees: FeesPreview(base: fees.baseFee, priority: fees.priorityFee, tip: fees.tipAmount),
            warnings: [],
            simulation: nil,
            balanceChanges: [
                IntentBalanceChange(token: "SOL", amount: "-\(formatAmount(sol + fees.totalSOL))"),
                IntentBalanceChange(token: lstName, amount: "+\(formatAmount(sol))") // approximate 1:1
            ]
        )

        return IntentRouterResult(
            payload: .stakeBundle(stake: stakeTx, tip: tipTx),
            preview: preview,
            fees: fees
        )
    }

    // MARK: - Sign Message

    /// Solana off-chain message prefix to prevent signing arbitrary transactions.
    /// A valid Solana transaction never starts with 0xff, so prefixed messages cannot be replayed.
    private static let offchainMessagePrefix = Data([0xff] + Array("solana offchain".utf8))
    private static let maxMessageLength = 1232 // Solana MTU

    private func handleSignMessage(
        _ params: SignMessageParams,
        signer: TransactionSigner
    ) async throws -> IntentRouterResult {
        guard params.message.utf8.count <= Self.maxMessageLength else {
            throw IntentRouterError.invalidParams("Message too long: \(params.message.utf8.count) bytes (max \(Self.maxMessageLength))")
        }
        let messageData = Self.offchainMessagePrefix + Data(params.message.utf8)
        let signature = try await signer.sign(message: messageData)

        let preview = IntentPreview(
            action: IntentServer.describeIntent(IntentRequest(
                type: .signMessage,
                params: .signMessage(params),
                metadata: nil
            )),
            fees: FeesPreview(base: 0, priority: 0, tip: 0),
            warnings: [],
            simulation: nil,
            balanceChanges: nil
        )

        return IntentRouterResult(
            payload: .signedMessage(signature: signature),
            preview: preview,
            fees: TransactionFees(baseFee: 0, priorityFee: 0, tipAmount: 0)
        )
    }

    // MARK: - Create Wallet

    private func handleCreateWallet(_ request: IntentRequest) async throws -> IntentRouterResult {
        // Preview only — key material is NOT generated here.
        // Generation happens after user approval in the signing prompt's approve() flow.
        let preview = IntentPreview(
            action: "Create new hot wallet",
            fees: FeesPreview(base: 0, priority: 0, tip: 0),
            warnings: ["A new keypair will be generated and stored in Keychain upon approval."],
            simulation: nil,
            balanceChanges: nil
        )

        // Use a deferred payload that signals the signing prompt to generate the key
        return IntentRouterResult(
            payload: .walletCreated(address: "pending_creation"),
            preview: preview,
            fees: TransactionFees(baseFee: 0, priorityFee: 0, tipAmount: 0)
        )
    }

    // MARK: - Batch

    /// Maximum number of sub-intents allowed in a single batch.
    static let maxBatchSize = 10

    private func handleBatch(
        _ params: BatchParams,
        signer: TransactionSigner
    ) async throws -> IntentRouterResult {
        guard !params.intents.isEmpty else {
            throw IntentRouterError.invalidParams("Batch must contain at least one intent")
        }

        // Enforce max batch size
        guard params.intents.count <= Self.maxBatchSize else {
            throw IntentRouterError.invalidParams("Batch too large: \(params.intents.count) intents (max \(Self.maxBatchSize))")
        }

        // Reject nested batches
        for intent in params.intents {
            if case .batch = intent.params {
                throw IntentRouterError.invalidParams("Nested batches are not allowed")
            }
        }

        // Build preview for all sub-intents
        var actionLines: [String] = []
        for (i, intent) in params.intents.enumerated() {
            let description = IntentServer.describeIntent(intent)
            actionLines.append("\(i + 1). \(description)")
        }

        let preview = IntentPreview(
            action: "Batch (\(params.intents.count) operations):\n" + actionLines.joined(separator: "\n"),
            fees: nil,
            warnings: params.intents.count > 5 ? ["Large batch: \(params.intents.count) operations"] : [],
            simulation: nil,
            balanceChanges: nil
        )

        // Execute each sub-intent sequentially
        var results: [IntentRouterResult] = []
        var totalBaseFee: UInt64 = 0
        var totalPriorityFee: UInt64 = 0
        var totalTip: UInt64 = 0

        for (i, subIntent) in params.intents.enumerated() {
            do {
                let result = try await processIntent(subIntent, signer: signer)
                results.append(result)
                totalBaseFee += result.fees.baseFee
                totalPriorityFee += result.fees.priorityFee
                totalTip += result.fees.tipAmount
            } catch {
                throw IntentRouterError.buildFailed("Batch sub-intent \(i + 1) failed: \(error.localizedDescription)")
            }
        }

        // Use the first result's payload for the batch response, with aggregated preview
        let batchPreview = IntentPreview(
            action: preview.action,
            fees: FeesPreview(base: totalBaseFee, priority: totalPriorityFee, tip: totalTip),
            warnings: preview.warnings,
            simulation: nil,
            balanceChanges: nil
        )

        // Return first result's payload (caller handles submitting all)
        return IntentRouterResult(
            payload: results.first?.payload ?? .walletCreated(address: "batch_empty"),
            preview: batchPreview,
            fees: TransactionFees(baseFee: totalBaseFee, priorityFee: totalPriorityFee, tipAmount: totalTip)
        )
    }

    // MARK: - Simulation

    private func simulateTransaction(_ tx: Transaction) async -> SimulationResult? {
        let base64 = tx.serializeBase64()
        do {
            let result = try await rpcClient.simulateTransaction(encodedTransaction: base64)
            return SimulationResult(
                success: result.err == nil,
                computeUnitsUsed: result.unitsConsumed,
                error: result.err.map { "\($0)" }
            )
        } catch {
            return SimulationResult(success: false, computeUnitsUsed: nil, error: error.localizedDescription)
        }
    }

    // MARK: - Token Lookups

    private func lookupTokenName(_ mint: String) async -> String {
        // Well-known tokens
        switch mint {
        case "So11111111111111111111111111111111111111112": return "SOL"
        case "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v": return "USDC"
        case "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB": return "USDT"
        case "J1toso1uCk3RLmjorhTtrVwY9HJ7X8V9yYac6Y7kGCPn": return "JitoSOL"
        case "mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So": return "mSOL"
        case "bSo13r4TkiE4KumL71LsHTPpL2euBYLFx6h9HP3piy1": return "bSOL"
        default:
            // Check wallet service token definitions
            let definitions = await MainActor.run { walletService.tokenDefinitions }
            if let def = definitions.first(where: { $0.mint == mint }) {
                return def.name
            }
            return String(mint.prefix(8)) + "..."
        }
    }

    private func lookupDecimals(_ mint: String) async -> Int {
        switch mint {
        case "So11111111111111111111111111111111111111112": return 9
        case "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v": return 6
        case "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB": return 6
        default:
            let definitions = await MainActor.run { walletService.tokenDefinitions }
            if let def = definitions.first(where: { $0.mint == mint }) {
                return def.decimals
            }
            return 9 // default
        }
    }

    // MARK: - Warnings

    private func buildWarnings(solAmount: Double) -> [String] {
        var warnings: [String] = []
        if solAmount > 10 {
            warnings.append("Large transfer: \(formatAmount(solAmount)) SOL")
        }
        return warnings
    }

    private func buildSwapWarnings(quote: JupiterQuote) -> [String] {
        var warnings: [String] = []
        if let pctStr = quote.priceImpactPct, let priceImpact = Double(pctStr), priceImpact > 1.0 {
            warnings.append("High price impact: \(String(format: "%.2f", priceImpact))%")
        }
        return warnings
    }

    // MARK: - Formatting

    private func formatAmount(_ amount: Double) -> String {
        if amount == 0 { return "0" }
        if amount >= 1000 {
            return String(format: "%.2f", amount)
        } else if amount >= 1 {
            return String(format: "%.4f", amount)
        } else {
            return String(format: "%.6f", amount)
        }
    }
}

// MARK: - Intent Router Errors

enum IntentRouterError: Error, LocalizedError {
    case unsupported(String)
    case invalidParams(String)
    case buildFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let msg): return "Unsupported: \(msg)"
        case .invalidParams(let msg): return "Invalid params: \(msg)"
        case .buildFailed(let msg): return "Build failed: \(msg)"
        }
    }
}
