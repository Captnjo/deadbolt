import Foundation
import SwiftUI
import DeadboltCore
#if os(macOS)
import HardwareWallet
#endif

/// P4-012: View model for swaps via Jupiter or DFlow.
/// Orchestrates: select input -> select output -> enter amount -> get quote -> preview -> approve -> submit.
@MainActor
final class SwapViewModel: ObservableObject {
    enum Step {
        case inputSelect
        case outputSelect
        case quote
        case preview
        case confirming
    }

    enum SwapAggregator: String {
        case jupiter
        case dflow

        var displayName: String {
            switch self {
            case .jupiter: return "Jupiter"
            case .dflow: return "DFlow"
            }
        }
    }

    @Published var step: Step = .inputSelect
    @Published var inputToken: SwapToken?
    @Published var outputToken: SwapOutputToken?
    @Published var amountString: String = ""
    @Published var jupiterQuote: JupiterQuote?
    @Published var dflowOrder: DFlowOrder?
    @Published var fees: TransactionFees?
    @Published var isQuoting: Bool = false
    @Published var errorMessage: String?
    @Published var aggregator: SwapAggregator

    let confirmationTracker: ConfirmationTracker

    private let walletService: WalletService
    private let authService: AuthService
    private let transactionBuilder: TransactionBuilder
    private let jupiterClient: JupiterClient
    private let dflowClient: DFlowClient
    private let rpcClient: SolanaRPCClient
    private var quoteRefreshTask: Task<Void, Never>?
    #if os(macOS)
    private var esp32Bridge: ESP32SerialBridge?
    #endif

    init(walletService: WalletService, authService: AuthService) {
        self.walletService = walletService
        self.authService = authService
        let rpcURL = AppConfig.defaultRPCURL
        self.rpcClient = SolanaRPCClient(rpcURL: rpcURL)
        self.transactionBuilder = TransactionBuilder(rpcClient: rpcClient)
        self.jupiterClient = JupiterClient(apiKey: AppConfig.defaultJupiterAPIKey)
        self.dflowClient = DFlowClient(apiKey: AppConfig.defaultDFlowAPIKey)
        self.confirmationTracker = ConfirmationTracker(rpcClient: rpcClient)
        self.aggregator = SwapAggregator(rawValue: AppConfig.defaultPreferredSwapAggregator) ?? .dflow
    }

    var inputAmountRaw: UInt64 {
        guard let token = inputToken else { return 0 }
        guard let decimal = Decimal(string: amountString), decimal > 0 else { return 0 }
        var multiplier = Decimal(1)
        for _ in 0..<token.decimals { multiplier *= 10 }
        let raw = decimal * multiplier
        return NSDecimalNumber(decimal: raw).uint64Value
    }

    var canGetQuote: Bool {
        inputToken != nil && outputToken != nil && inputAmountRaw > 0
    }

    // MARK: - Navigation

    func selectInput(_ token: SwapToken) {
        inputToken = token
        step = .outputSelect
    }

    func selectOutput(_ token: SwapOutputToken) {
        outputToken = token
        step = .quote
    }

    func goBack() {
        stopQuoteRefresh()
        switch step {
        case .inputSelect: break
        case .outputSelect: step = .inputSelect
        case .quote: step = .outputSelect
        case .preview: step = .quote
        case .confirming: break
        }
    }

    // MARK: - Quoting

    /// Whether there's an active quote/order from either aggregator.
    var hasQuote: Bool {
        switch aggregator {
        case .jupiter: return jupiterQuote != nil
        case .dflow: return dflowOrder != nil
        }
    }

    func fetchQuote() {
        guard let input = inputToken, let output = outputToken else { return }
        guard inputAmountRaw > 0 else {
            errorMessage = "Enter an amount"
            return
        }

        // Don't swap same token
        if input.mint == output.mint {
            errorMessage = "Input and output tokens must be different"
            return
        }

        // Validate API key for selected aggregator
        switch aggregator {
        case .dflow:
            if AppConfig.defaultDFlowAPIKey.isEmpty {
                errorMessage = "DFlow API key required. Set it in Settings."
                return
            }
        case .jupiter:
            break // Jupiter works without a key (rate-limited)
        }

        isQuoting = true
        errorMessage = nil

        Task {
            do {
                switch aggregator {
                case .jupiter:
                    let quote = try await jupiterClient.getQuote(
                        inputMint: input.mint,
                        outputMint: output.mint,
                        amount: inputAmountRaw,
                        slippageBps: 50
                    )
                    self.jupiterQuote = quote
                    self.dflowOrder = nil
                case .dflow:
                    guard let wallet = walletService.activeWallet else {
                        throw SolanaError.decodingError("No wallet selected")
                    }
                    let order = try await dflowClient.getOrder(
                        inputMint: input.mint,
                        outputMint: output.mint,
                        amount: inputAmountRaw,
                        slippageBps: 50,
                        userPublicKey: wallet.address
                    )
                    self.dflowOrder = order
                    self.jupiterQuote = nil
                }
                self.isQuoting = false
                startQuoteRefresh()
            } catch {
                self.errorMessage = error.localizedDescription
                self.isQuoting = false
            }
        }
    }

    func refreshQuote() {
        guard let input = inputToken, let output = outputToken else { return }
        guard inputAmountRaw > 0 else { return }

        isQuoting = true

        Task {
            do {
                switch aggregator {
                case .jupiter:
                    let quote = try await jupiterClient.getQuote(
                        inputMint: input.mint,
                        outputMint: output.mint,
                        amount: inputAmountRaw,
                        slippageBps: 50
                    )
                    self.jupiterQuote = quote
                case .dflow:
                    guard let wallet = walletService.activeWallet else { return }
                    let order = try await dflowClient.getOrder(
                        inputMint: input.mint,
                        outputMint: output.mint,
                        amount: inputAmountRaw,
                        slippageBps: 50,
                        userPublicKey: wallet.address
                    )
                    self.dflowOrder = order
                }
            } catch {
                // Don't overwrite existing quote on refresh failure
            }
            self.isQuoting = false
        }
    }

    /// Switch aggregator and re-fetch the quote.
    func switchAggregator(to newAggregator: SwapAggregator) {
        guard newAggregator != aggregator else { return }
        stopQuoteRefresh()
        aggregator = newAggregator
        jupiterQuote = nil
        dflowOrder = nil
        if canGetQuote {
            fetchQuote()
        }
    }

    private func startQuoteRefresh() {
        stopQuoteRefresh()
        quoteRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                if Task.isCancelled { break }
                refreshQuote()
            }
        }
    }

    private func stopQuoteRefresh() {
        quoteRefreshTask?.cancel()
        quoteRefreshTask = nil
    }

    // MARK: - Preview & Submit

    func proceedToPreview() {
        stopQuoteRefresh()
        step = .preview
    }

    func approve() async {
        guard let wallet = walletService.activeWallet,
              let input = inputToken,
              let output = outputToken else {
            errorMessage = "Missing wallet or quote"
            return
        }

        // Ensure we have a quote/order for the current aggregator
        switch aggregator {
        case .jupiter:
            guard jupiterQuote != nil else {
                errorMessage = "Missing Jupiter quote"
                return
            }
        case .dflow:
            guard dflowOrder != nil else {
                errorMessage = "Missing DFlow order"
                return
            }
        }

        step = .confirming
        errorMessage = nil

        do {
            if wallet.source != .hardware {
                guard await authService.authenticate(reason: "Approve swap signing") else {
                    errorMessage = "Authentication required"
                    return
                }
            }

            let signer = try await loadSigner(for: wallet)

            switch aggregator {
            case .jupiter:
                try await approveJupiter(wallet: wallet, input: input, output: output, signer: signer)
            case .dflow:
                try await approveDFlow(wallet: wallet, input: input, output: output, signer: signer)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func approveJupiter(wallet: Wallet, input: SwapToken, output: SwapOutputToken, signer: TransactionSigner) async throws {
        guard let quote = jupiterQuote else { return }

        // Re-fetch a fresh quote to avoid stale pricing
        let freshQuote = try await jupiterClient.getQuote(
            inputMint: input.mint,
            outputMint: output.mint,
            amount: inputAmountRaw,
            slippageBps: 50
        )

        // Check if the price has moved significantly from what was shown
        let displayedOut = UInt64(quote.outAmount) ?? 0
        let freshOut = UInt64(freshQuote.outAmount) ?? 0
        if displayedOut > 0 && freshOut < displayedOut * 95 / 100 {
            self.jupiterQuote = freshQuote
            errorMessage = "Price moved significantly since preview. Please review the new quote."
            step = .quote
            startQuoteRefresh()
            return
        }

        let (transaction, txFees) = try await transactionBuilder.buildSwap(
            quote: freshQuote,
            userPublicKey: wallet.address,
            signer: signer
        )
        self.fees = txFees
        self.jupiterQuote = freshQuote

        let bundleId = try await transactionBuilder.submitSwapViaJito(transaction: transaction)
        await confirmationTracker.trackBundle(bundleId: bundleId)
    }

    private func approveDFlow(wallet: Wallet, input: SwapToken, output: SwapOutputToken, signer: TransactionSigner) async throws {
        // Re-fetch a fresh order to avoid stale transaction
        let freshOrder = try await dflowClient.getOrder(
            inputMint: input.mint,
            outputMint: output.mint,
            amount: inputAmountRaw,
            slippageBps: 50,
            userPublicKey: wallet.address
        )
        self.dflowOrder = freshOrder

        let transaction = try await transactionBuilder.buildDFlowSwap(
            orderBase64: freshOrder.transactionBase64,
            signer: signer
        )

        let baseFee: UInt64 = 5000
        self.fees = TransactionFees(baseFee: baseFee, priorityFee: 0, tipAmount: 0)

        let signature = try await transactionBuilder.submitDFlowSwap(transaction: transaction)
        await confirmationTracker.track(signature: signature)
    }

    private func loadSigner(for wallet: Wallet) async throws -> TransactionSigner {
        switch wallet.source {
        case .keypairFile(let path):
            let keypair = try KeypairReader.read(from: path)
            return try SoftwareSigner(keypair: keypair)
        case .keychain:
            let seed = try KeychainManager.retrieveSeed(address: wallet.address)
            return try SoftwareSigner(seed: seed)
        case .hardware:
            #if os(macOS)
            let detector = ESP32Detector()
            let ports = await detector.scan()
            guard let portPath = ports.first else {
                throw SolanaError.decodingError("No ESP32 hardware wallet detected.")
            }
            guard let port = ORSSerialPortAdapter(path: portPath, baudRate: ESP32SerialBridge.defaultBaudRate) else {
                throw SolanaError.decodingError("Failed to open serial port at \(portPath)")
            }
            let bridge = ESP32SerialBridge(port: port)
            try await bridge.connect()
            // Verify device identity matches registered wallet
            let devicePubkey = await bridge.publicKey
            if let wallet = walletService.activeWallet, devicePubkey.base58 != wallet.address {
                await bridge.disconnect()
                throw SolanaError.decodingError("Hardware wallet public key mismatch. Expected \(wallet.address.prefix(8))..., got \(devicePubkey.base58.prefix(8))...")
            }
            self.esp32Bridge = bridge
            return bridge
            #else
            throw SolanaError.decodingError("Hardware wallet not supported on iOS")
            #endif
        }
    }

    deinit {
        quoteRefreshTask?.cancel()
    }
}
