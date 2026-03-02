import Foundation
import SwiftUI
import DeadboltCore
#if os(macOS)
import HardwareWallet
#endif

@MainActor
final class SendViewModel: ObservableObject {
    enum Step {
        case recipient
        case amount
        case preview
        case confirming
    }

    @Published var step: Step = .recipient
    @Published var recipientAddress: String = ""
    @Published var recipientValid: Bool = false
    @Published var amountString: String = ""
    @Published var fees: TransactionFees?
    @Published var simulationStatus: TransactionPreviewView.SimulationStatus = .pending
    @Published var errorMessage: String?
    @Published var hardwareWalletPrompt: String?

    let confirmationTracker: ConfirmationTracker

    private let walletService: WalletService
    private let authService: AuthService
    private let transactionBuilder: TransactionBuilder
    private let rpcClient: SolanaRPCClient
    #if os(macOS)
    private var esp32Bridge: ESP32SerialBridge?
    #endif

    var amountSOL: Double { Double(amountString) ?? 0 }
    var amountLamports: UInt64 {
        guard let decimal = Decimal(string: amountString), decimal > 0 else { return 0 }
        let lamports = decimal * 1_000_000_000
        let rounded = NSDecimalNumber(decimal: lamports).uint64Value
        return rounded
    }

    init(walletService: WalletService, authService: AuthService) {
        self.walletService = walletService
        self.authService = authService
        let rpcURL = AppConfig.defaultRPCURL
        self.rpcClient = SolanaRPCClient(rpcURL: rpcURL)
        self.transactionBuilder = TransactionBuilder(rpcClient: rpcClient)
        self.confirmationTracker = ConfirmationTracker(rpcClient: rpcClient)
    }

    var canProceedToAmount: Bool {
        recipientValid
    }

    var canProceedToPreview: Bool {
        amountSOL > 0 && amountSOL <= Double(walletService.solBalance) / 1_000_000_000.0
    }

    func proceedToAmount() {
        step = .amount
    }

    func proceedToPreview() {
        step = .preview
        simulateTransaction()
    }

    func goBack() {
        switch step {
        case .recipient: break
        case .amount: step = .recipient
        case .preview: step = .amount
        case .confirming: break
        }
    }

    /// Whether the active wallet is a hardware wallet.
    var isHardwareWallet: Bool {
        walletService.activeWallet?.source == .hardware
    }

    func approve() async {
        guard let wallet = walletService.activeWallet else {
            errorMessage = "No wallet selected"
            return
        }

        // Block submission if simulation failed
        if case .failed = simulationStatus {
            errorMessage = "Transaction simulation failed. Cannot submit."
            return
        }

        step = .confirming
        errorMessage = nil
        hardwareWalletPrompt = nil

        do {
            // Require auth for hot wallets
            if !isHardwareWallet {
                guard await authService.authenticate(reason: "Approve transaction signing") else {
                    errorMessage = "Authentication required"
                    return
                }
            }

            let signer = try await loadSigner(for: wallet)
            let recipient = try SolanaPublicKey(base58: recipientAddress)

            // Show a "preparing" prompt — the real "press button" prompt appears
            // via the onAwaitingConfirmation callback once the ESP32 is actually ready
            if isHardwareWallet {
                hardwareWalletPrompt = "Preparing transaction for hardware signing..."
            }

            // Build and sign transaction (no Jito tip on devnet)
            let tip: UInt64 = AppConfig.defaultNetwork == .mainnet ? JitoTip.defaultTipLamports : 0
            let (transaction, txFees) = try await transactionBuilder.buildSendSOL(
                from: signer,
                to: recipient,
                lamports: amountLamports,
                tipLamports: tip
            )
            self.fees = txFees
            hardwareWalletPrompt = nil

            // Submit via Jito on mainnet, standard RPC on devnet
            let signature: String
            if AppConfig.defaultNetwork == .mainnet {
                signature = try await transactionBuilder.submitViaJito(transaction: transaction)
            } else {
                signature = try await transactionBuilder.submitViaRPC(transaction: transaction)
            }

            // Track confirmation
            await confirmationTracker.track(signature: signature)
        } catch {
            hardwareWalletPrompt = nil
            errorMessage = error.localizedDescription
        }
    }

    private func simulateTransaction() {
        simulationStatus = .pending

        // Skip simulation for hardware wallets — connecting to ESP32 just for
        // simulation is disruptive and can fail. The real signing happens in approve().
        if isHardwareWallet {
            let tip: UInt64 = AppConfig.defaultNetwork == .mainnet ? JitoTip.defaultTipLamports : 0
            fees = TransactionFees(baseFee: 5000, priorityFee: 0, tipAmount: tip)
            simulationStatus = .success(computeUnits: 0)
            return
        }

        Task {
            do {
                guard let wallet = walletService.activeWallet else { return }
                let signer = try await loadSigner(for: wallet)
                let recipient = try SolanaPublicKey(base58: recipientAddress)

                let simTip: UInt64 = AppConfig.defaultNetwork == .mainnet ? JitoTip.defaultTipLamports : 0
                let (transaction, txFees) = try await transactionBuilder.buildSendSOL(
                    from: signer,
                    to: recipient,
                    lamports: amountLamports,
                    tipLamports: simTip
                )
                self.fees = txFees

                let result = try await rpcClient.simulateTransaction(
                    encodedTransaction: transaction.serializeBase64()
                )

                if result.err != nil {
                    simulationStatus = .failed(error: "Simulation failed")
                } else {
                    simulationStatus = .success(computeUnits: result.unitsConsumed ?? 0)
                }
            } catch {
                simulationStatus = .failed(error: error.localizedDescription)
            }
        }
    }

    /// Load the appropriate signer for the given wallet source.
    /// For hardware wallets, connects to the ESP32 serial bridge.
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
            return try await loadHardwareSigner()
            #else
            throw SolanaError.decodingError("Hardware wallet is not supported on iOS")
            #endif
        }
    }

    #if os(macOS)
    /// Connect to the ESP32 hardware wallet and return it as a signer.
    private func loadHardwareSigner() async throws -> TransactionSigner {
        let detector = ESP32Detector()
        let ports = await detector.scan()

        guard let portPath = ports.first else {
            throw SolanaError.decodingError("No ESP32 hardware wallet detected. Please connect your device.")
        }

        guard let port = ORSSerialPortAdapter(path: portPath, baudRate: ESP32SerialBridge.defaultBaudRate) else {
            throw SolanaError.decodingError("Failed to open serial port at \(portPath)")
        }

        // The callback fires when the ESP32 enters AWAITING_CONFIRM (after "pending" response).
        // Only then should the user press the BOOT button.
        let bridge = ESP32SerialBridge(port: port, onAwaitingConfirmation: { [weak self] in
            Task { @MainActor [weak self] in
                self?.hardwareWalletPrompt = "Press BOOT button on ESP32 to approve transaction"
            }
        })
        try await bridge.connect()

        // Verify device identity matches registered wallet
        let devicePubkey = await bridge.publicKey
        if let wallet = walletService.activeWallet, devicePubkey.base58 != wallet.address {
            await bridge.disconnect()
            throw SolanaError.decodingError("Hardware wallet public key mismatch. Expected \(wallet.address.prefix(8))..., got \(devicePubkey.base58.prefix(8))...")
        }

        self.esp32Bridge = bridge
        return bridge
    }
    #endif
}
