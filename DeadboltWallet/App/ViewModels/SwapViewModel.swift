import Foundation
import SwiftUI
import DeadboltCore
import LocalAuthentication
#if os(macOS)
import HardwareWallet
#endif

/// P4-012: View model for Jupiter swaps.
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

    @Published var step: Step = .inputSelect
    @Published var inputToken: SwapToken?
    @Published var outputToken: SwapOutputToken?
    @Published var amountString: String = ""
    @Published var jupiterQuote: JupiterQuote?
    @Published var fees: TransactionFees?
    @Published var isQuoting: Bool = false
    @Published var errorMessage: String?

    let confirmationTracker: ConfirmationTracker

    private let walletService: WalletService
    private let transactionBuilder: TransactionBuilder
    private let jupiterClient: JupiterClient
    private let rpcClient: SolanaRPCClient
    private var quoteRefreshTask: Task<Void, Never>?
    #if os(macOS)
    private var esp32Bridge: ESP32SerialBridge?
    #endif

    init(walletService: WalletService) {
        self.walletService = walletService
        let rpcURL = AppConfig.defaultRPCURL
        self.rpcClient = SolanaRPCClient(rpcURL: rpcURL)
        self.transactionBuilder = TransactionBuilder(rpcClient: rpcClient)
        self.jupiterClient = JupiterClient()
        self.confirmationTracker = ConfirmationTracker(rpcClient: rpcClient)
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

        isQuoting = true
        errorMessage = nil

        Task {
            do {
                let quote = try await jupiterClient.getQuote(
                    inputMint: input.mint,
                    outputMint: output.mint,
                    amount: inputAmountRaw,
                    slippageBps: 50 // 0.5% default slippage
                )
                self.jupiterQuote = quote
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
                let quote = try await jupiterClient.getQuote(
                    inputMint: input.mint,
                    outputMint: output.mint,
                    amount: inputAmountRaw,
                    slippageBps: 50
                )
                self.jupiterQuote = quote
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
              let quote = jupiterQuote,
              let input = inputToken,
              let output = outputToken else {
            errorMessage = "Missing wallet or quote"
            return
        }

        step = .confirming
        errorMessage = nil

        do {
            if wallet.source != .hardware {
                try await authenticateUser()
            }

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
                // Output dropped by more than 5% from what was shown
                self.jupiterQuote = freshQuote
                errorMessage = "Price moved significantly since preview. Please review the new quote."
                step = .quote
                startQuoteRefresh()
                return
            }

            let signer = try await loadSigner(for: wallet)

            let (transaction, txFees) = try await transactionBuilder.buildSwap(
                quote: freshQuote,
                userPublicKey: wallet.address,
                signer: signer
            )
            self.fees = txFees
            self.jupiterQuote = freshQuote

            let bundleId = try await transactionBuilder.submitSwapViaJito(transaction: transaction)
            await confirmationTracker.trackBundle(bundleId: bundleId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func authenticateUser() async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            #if DEBUG
            return // Allow through in debug builds (VMs, CI)
            #else
            throw SolanaError.authenticationFailed("Device authentication is required but not configured. Set a password or enable Touch ID in System Settings.")
            #endif
        }
        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Approve swap signing")
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
