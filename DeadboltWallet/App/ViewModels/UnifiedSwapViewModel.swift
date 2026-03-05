import Foundation
import SwiftUI
import DeadboltCore
#if os(macOS)
import HardwareWallet
#endif

/// Unified swap view model with single-page layout.
/// Both token selectors visible, live debounced quotes as user types.
@MainActor
final class UnifiedSwapViewModel: ObservableObject {
    enum Phase {
        case editing
        case reviewing
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

    @Published var phase: Phase = .editing
    @Published var inputToken: SwapToken? = .sol
    @Published var outputToken: SwapOutputToken?
    @Published var amountString: String = ""
    @Published var jupiterQuote: JupiterQuote?
    @Published var dflowOrder: DFlowOrder?
    @Published var fees: TransactionFees?
    @Published var isQuoting: Bool = false
    @Published var errorMessage: String?
    @Published var aggregator: SwapAggregator
    @Published var simulationStatus: TransactionPreviewView.SimulationStatus = .pending

    let confirmationTracker: ConfirmationTracker
    let signerLoader: SignerLoader

    private let walletService: WalletService
    private let authService: AuthService
    private let transactionBuilder: TransactionBuilder
    private let jupiterClient: JupiterClient
    private let dflowClient: DFlowClient
    private let rpcClient: SolanaRPCClient
    private var quoteRefreshTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    init(walletService: WalletService, authService: AuthService) {
        self.walletService = walletService
        self.authService = authService
        let rpcURL = AppConfig.defaultRPCURL
        self.rpcClient = SolanaRPCClient(rpcURL: rpcURL)
        self.transactionBuilder = TransactionBuilder(rpcClient: rpcClient)
        self.jupiterClient = JupiterClient(apiKey: AppConfig.defaultJupiterAPIKey)
        self.dflowClient = DFlowClient(apiKey: AppConfig.defaultDFlowAPIKey)
        self.confirmationTracker = ConfirmationTracker(rpcClient: rpcClient)
        self.signerLoader = SignerLoader(walletService: walletService)
        self.aggregator = SwapAggregator(rawValue: AppConfig.defaultPreferredSwapAggregator) ?? .dflow
    }

    // MARK: - Computed Properties

    var inputAmountRaw: UInt64 {
        guard let token = inputToken else { return 0 }
        guard let decimal = Decimal(string: amountString), decimal > 0 else { return 0 }
        var multiplier = Decimal(1)
        for _ in 0..<token.decimals { multiplier *= 10 }
        let raw = decimal * multiplier
        return NSDecimalNumber(decimal: raw).uint64Value
    }

    var hasQuote: Bool {
        switch aggregator {
        case .jupiter: return jupiterQuote != nil
        case .dflow: return dflowOrder != nil
        }
    }

    var canReview: Bool {
        inputToken != nil && outputToken != nil && inputAmountRaw > 0 && hasQuote
    }

    var outputAmountDisplay: String {
        guard let quote = jupiterQuote, let output = outputToken else { return "" }
        let amount = (Double(quote.outAmount) ?? 0) / pow(10.0, Double(output.decimals))
        return DashboardViewModel.formatTokenAmount(amount)
    }

    var actionDescription: String {
        let inputName = inputToken?.name ?? "?"
        let outputName = outputToken?.name ?? "?"

        switch aggregator {
        case .jupiter:
            if let quote = jupiterQuote, let output = outputToken {
                let inputAmt = (Double(quote.inAmount) ?? 0) / pow(10.0, Double(inputToken?.decimals ?? 9))
                let outputAmt = (Double(quote.outAmount) ?? 0) / pow(10.0, Double(output.decimals))
                return "Swap \(DashboardViewModel.formatTokenAmount(inputAmt)) \(inputName) for ~\(DashboardViewModel.formatTokenAmount(outputAmt)) \(outputName) via Jupiter"
            }
        case .dflow:
            if dflowOrder != nil {
                return "Swap \(amountString) \(inputName) for \(outputName) via DFlow"
            }
        }
        return "Swap \(inputName) for \(outputName)"
    }

    // MARK: - Token Switching

    func swapDirection() {
        guard let input = inputToken, let output = outputToken else { return }

        // Convert current output to input
        let newInput: SwapToken
        if output.mint == LSTMint.wrappedSOL {
            newInput = .sol
        } else {
            // Check if user has this token in balances
            if let tb = walletService.tokenBalances.first(where: { $0.definition.mint == output.mint }) {
                newInput = .token(tb)
            } else {
                return // Can't swap to a token not in wallet
            }
        }

        // Convert current input to output
        let newOutput = SwapOutputToken(mint: input.mint, name: input.name, decimals: input.decimals)

        inputToken = newInput
        outputToken = newOutput
        amountString = ""
        clearQuotes()
    }

    // MARK: - Phase Navigation

    func review() {
        phase = .reviewing
        simulationStatus = .skipped // Swaps don't simulate
    }

    func edit() {
        phase = .editing
        errorMessage = nil
    }

    // MARK: - Debounced Quoting

    /// Called when amount or tokens change to debounce quote fetching.
    func onInputChanged() {
        debounceTask?.cancel()
        guard inputToken != nil, outputToken != nil, inputAmountRaw > 0 else {
            clearQuotes()
            return
        }

        // Validate same token
        if let input = inputToken, let output = outputToken, input.mint == output.mint {
            errorMessage = "Input and output tokens must be different"
            return
        }

        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            if Task.isCancelled { return }
            fetchQuote()
        }
    }

    func switchAggregator(to newAggregator: SwapAggregator) {
        guard newAggregator != aggregator else { return }
        stopQuoteRefresh()
        aggregator = newAggregator
        clearQuotes()
        if inputToken != nil && outputToken != nil && inputAmountRaw > 0 {
            fetchQuote()
        }
    }

    // MARK: - Quote Fetching

    private func fetchQuote() {
        guard let input = inputToken, let output = outputToken else { return }
        guard inputAmountRaw > 0 else {
            errorMessage = "Enter an amount"
            return
        }

        if input.mint == output.mint {
            errorMessage = "Input and output tokens must be different"
            return
        }

        switch aggregator {
        case .dflow:
            if AppConfig.defaultDFlowAPIKey.isEmpty {
                errorMessage = "DFlow API key required. Set it in Settings."
                return
            }
        case .jupiter:
            break
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

    private func startQuoteRefresh() {
        stopQuoteRefresh()
        quoteRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { break }
                refreshQuote()
            }
        }
    }

    private func stopQuoteRefresh() {
        quoteRefreshTask?.cancel()
        quoteRefreshTask = nil
    }

    private func clearQuotes() {
        stopQuoteRefresh()
        jupiterQuote = nil
        dflowOrder = nil
        errorMessage = nil
    }

    // MARK: - Approve & Submit

    func approve() async {
        guard let wallet = walletService.activeWallet,
              let input = inputToken,
              let output = outputToken else {
            errorMessage = "Missing wallet or tokens"
            return
        }

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

        phase = .confirming
        errorMessage = nil
        signerLoader.clearPrompt()

        do {
            if !signerLoader.isHardwareWallet {
                guard await authService.authenticate(reason: "Approve swap signing") else {
                    errorMessage = "Authentication required"
                    phase = .reviewing
                    return
                }
            }

            if signerLoader.isHardwareWallet {
                signerLoader.hardwareWalletPrompt = "Preparing transaction for hardware signing..."
            }

            let signer = try await signerLoader.loadSigner(for: wallet)

            switch aggregator {
            case .jupiter:
                try await approveJupiter(wallet: wallet, input: input, output: output, signer: signer)
            case .dflow:
                try await approveDFlow(wallet: wallet, input: input, output: output, signer: signer)
            }
        } catch {
            signerLoader.clearPrompt()
            errorMessage = error.localizedDescription
        }
    }

    private func approveJupiter(wallet: Wallet, input: SwapToken, output: SwapOutputToken, signer: TransactionSigner) async throws {
        guard let quote = jupiterQuote else { return }

        let freshQuote = try await jupiterClient.getQuote(
            inputMint: input.mint,
            outputMint: output.mint,
            amount: inputAmountRaw,
            slippageBps: 50
        )

        // Check for significant price movement
        let displayedOut = UInt64(quote.outAmount) ?? 0
        let freshOut = UInt64(freshQuote.outAmount) ?? 0
        if displayedOut > 0 && freshOut < displayedOut * 95 / 100 {
            self.jupiterQuote = freshQuote
            errorMessage = "Price moved significantly since preview. Please review the new quote."
            phase = .editing
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
        signerLoader.clearPrompt()

        let bundleId = try await transactionBuilder.submitSwapViaJito(transaction: transaction)
        await confirmationTracker.trackBundle(bundleId: bundleId)
    }

    private func approveDFlow(wallet: Wallet, input: SwapToken, output: SwapOutputToken, signer: TransactionSigner) async throws {
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

        self.fees = TransactionFees(baseFee: 5000, priorityFee: 0, tipAmount: 0)
        signerLoader.clearPrompt()

        let signature = try await transactionBuilder.submitDFlowSwap(transaction: transaction)
        await confirmationTracker.track(signature: signature)
    }

    deinit {
        quoteRefreshTask?.cancel()
        debounceTask?.cancel()
    }
}
