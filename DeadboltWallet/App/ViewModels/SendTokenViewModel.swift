import Foundation
import SwiftUI
import DeadboltCore
#if os(macOS)
import HardwareWallet
#endif

/// P3-011: View model for sending SPL tokens.
/// Orchestrates: recipient -> token select -> amount -> preview -> confirm.
@MainActor
final class SendTokenViewModel: ObservableObject {
    enum Step {
        case recipient
        case tokenSelect
        case amount
        case preview
        case confirming
    }

    @Published var step: Step = .recipient
    @Published var recipientAddress: String = ""
    @Published var recipientValid: Bool = false
    @Published var selectedToken: TokenBalance?
    @Published var amountString: String = ""
    @Published var fees: TransactionFees?
    @Published var simulationStatus: TransactionPreviewView.SimulationStatus = .pending
    @Published var errorMessage: String?

    let confirmationTracker: ConfirmationTracker

    private let walletService: WalletService
    private let authService: AuthService
    private let transactionBuilder: TransactionBuilder
    private let rpcClient: SolanaRPCClient
    #if os(macOS)
    private var esp32Bridge: ESP32SerialBridge?
    #endif

    init(walletService: WalletService, authService: AuthService) {
        self.walletService = walletService
        self.authService = authService
        let rpcURL = AppConfig.defaultRPCURL
        self.rpcClient = SolanaRPCClient(rpcURL: rpcURL)
        self.transactionBuilder = TransactionBuilder(rpcClient: rpcClient)
        self.confirmationTracker = ConfirmationTracker(rpcClient: rpcClient)
    }

    var amountToken: Double { Double(amountString) ?? 0 }

    var amountRaw: UInt64 {
        guard let token = selectedToken else { return 0 }
        guard let decimal = Decimal(string: amountString), decimal > 0 else { return 0 }
        var multiplier = Decimal(1)
        for _ in 0..<token.definition.decimals { multiplier *= 10 }
        let raw = decimal * multiplier
        return NSDecimalNumber(decimal: raw).uint64Value
    }

    var canProceedToTokenSelect: Bool {
        recipientValid
    }

    var canProceedToAmount: Bool {
        selectedToken != nil
    }

    var canProceedToPreview: Bool {
        guard let token = selectedToken else { return false }
        return amountToken > 0 && amountToken <= token.uiAmount
    }

    // MARK: - Navigation

    func proceedToTokenSelect() {
        step = .tokenSelect
    }

    func selectToken(_ token: TokenBalance) {
        selectedToken = token
        step = .amount
    }

    func proceedToPreview() {
        step = .preview
        simulateTransaction()
    }

    func goBack() {
        switch step {
        case .recipient: break
        case .tokenSelect: step = .recipient
        case .amount: step = .tokenSelect
        case .preview: step = .amount
        case .confirming: break
        }
    }

    // MARK: - Transaction

    func approve() async {
        guard let wallet = walletService.activeWallet else {
            errorMessage = "No wallet selected"
            return
        }
        guard let token = selectedToken else {
            errorMessage = "No token selected"
            return
        }

        // Block submission if simulation failed
        if case .failed = simulationStatus {
            errorMessage = "Transaction simulation failed. Cannot submit."
            return
        }

        step = .confirming
        errorMessage = nil

        do {
            if wallet.source != .hardware {
                guard await authService.authenticate(reason: "Approve token transfer signing") else {
                    errorMessage = "Authentication required"
                    return
                }
            }

            let signer = try await loadSigner(for: wallet)
            let recipient = try SolanaPublicKey(base58: recipientAddress)
            let mint = try SolanaPublicKey(base58: token.definition.mint)

            let (transaction, txFees) = try await transactionBuilder.buildSendToken(
                from: signer,
                to: recipient,
                mint: mint,
                amount: amountRaw,
                decimals: UInt8(token.definition.decimals)
            )
            self.fees = txFees

            let signature = try await transactionBuilder.submitViaJito(transaction: transaction)
            await confirmationTracker.track(signature: signature)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func simulateTransaction() {
        simulationStatus = .pending

        Task {
            do {
                guard let wallet = walletService.activeWallet,
                      let token = selectedToken else { return }
                let signer = try await loadSigner(for: wallet)
                let recipient = try SolanaPublicKey(base58: recipientAddress)
                let mint = try SolanaPublicKey(base58: token.definition.mint)

                let (transaction, txFees) = try await transactionBuilder.buildSendToken(
                    from: signer,
                    to: recipient,
                    mint: mint,
                    amount: amountRaw,
                    decimals: UInt8(token.definition.decimals)
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
}
