import Foundation
import SwiftUI
import DeadboltCore
import LocalAuthentication
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

    init(walletService: WalletService) {
        self.walletService = walletService
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
            // Require biometric/password auth for hot wallets
            if !isHardwareWallet {
                try await authenticateUser()
            }

            let signer = try await loadSigner(for: wallet)
            let recipient = try SolanaPublicKey(base58: recipientAddress)

            // Build and sign transaction
            let (transaction, txFees) = try await transactionBuilder.buildSendSOL(
                from: signer,
                to: recipient,
                lamports: amountLamports
            )
            self.fees = txFees

            // Submit via Jito
            let signature = try await transactionBuilder.submitViaJito(transaction: transaction)

            // Track confirmation
            await confirmationTracker.track(signature: signature)
        } catch {
            hardwareWalletPrompt = nil
            errorMessage = error.localizedDescription
        }
    }

    private func simulateTransaction() {
        simulationStatus = .pending

        Task {
            do {
                guard let wallet = walletService.activeWallet else { return }
                let signer = try await loadSigner(for: wallet)
                let recipient = try SolanaPublicKey(base58: recipientAddress)

                let (transaction, txFees) = try await transactionBuilder.buildSendSOL(
                    from: signer,
                    to: recipient,
                    lamports: amountLamports
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
        try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Approve transaction signing"
        )
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
        let bridge = ESP32SerialBridge(port: port)
        try await bridge.connect()

        // Verify device identity matches registered wallet
        let devicePubkey = await bridge.publicKey
        if let wallet = walletService.activeWallet, devicePubkey.base58 != wallet.address {
            await bridge.disconnect()
            throw SolanaError.decodingError("Hardware wallet public key mismatch. Expected \(wallet.address.prefix(8))..., got \(devicePubkey.base58.prefix(8))...")
        }

        self.esp32Bridge = bridge
        hardwareWalletPrompt = "Press BOOT button on ESP32 to approve transaction"
        return bridge
    }
    #endif
}
