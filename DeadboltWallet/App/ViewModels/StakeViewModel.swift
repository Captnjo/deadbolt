import Foundation
import SwiftUI
import DeadboltCore
import LocalAuthentication
#if os(macOS)
import HardwareWallet
#endif

/// P5-009: View model for liquid staking via Sanctum.
/// Orchestrates: enter amount -> select LST -> get quote -> preview -> approve -> submit.
@MainActor
final class StakeViewModel: ObservableObject {
    enum Step {
        case input
        case quote
        case preview
        case confirming
    }

    @Published var step: Step = .input
    @Published var amountString: String = ""
    @Published var selectedLST: LSTOption = .jitoSOL
    @Published var sanctumQuote: SanctumQuote?
    @Published var fees: TransactionFees?
    @Published var isQuoting: Bool = false
    @Published var errorMessage: String?

    let confirmationTracker: ConfirmationTracker

    private let walletService: WalletService
    private let transactionBuilder: TransactionBuilder
    private let sanctumClient: SanctumClient
    private let rpcClient: SolanaRPCClient
    #if os(macOS)
    private var esp32Bridge: ESP32SerialBridge?
    #endif

    init(walletService: WalletService) {
        self.walletService = walletService
        let rpcURL = AppConfig.defaultRPCURL
        self.rpcClient = SolanaRPCClient(rpcURL: rpcURL)
        self.transactionBuilder = TransactionBuilder(rpcClient: rpcClient)
        self.sanctumClient = SanctumClient()
        self.confirmationTracker = ConfirmationTracker(rpcClient: rpcClient)
    }

    var amountSOL: Double { Double(amountString) ?? 0 }
    var amountLamports: UInt64 {
        guard let decimal = Decimal(string: amountString), decimal > 0 else { return 0 }
        let lamports = decimal * 1_000_000_000
        return NSDecimalNumber(decimal: lamports).uint64Value
    }

    var canGetQuote: Bool {
        amountSOL > 0 && amountSOL <= Double(walletService.solBalance) / 1_000_000_000.0
    }

    // MARK: - Navigation

    func goBack() {
        switch step {
        case .input: break
        case .quote: step = .input
        case .preview: step = .quote
        case .confirming: break
        }
    }

    // MARK: - Quoting

    func fetchQuote() {
        guard amountLamports > 0 else {
            errorMessage = "Enter an amount"
            return
        }

        isQuoting = true
        errorMessage = nil
        step = .quote

        Task {
            do {
                let quote = try await sanctumClient.getQuote(
                    outputLstMint: selectedLST.mint,
                    amount: amountLamports
                )
                self.sanctumQuote = quote
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isQuoting = false
        }
    }

    func proceedToPreview() {
        step = .preview
    }

    // MARK: - Submit

    func approve() async {
        guard let wallet = walletService.activeWallet else {
            errorMessage = "No wallet selected"
            return
        }

        step = .confirming
        errorMessage = nil

        do {
            if wallet.source != .hardware {
                try await authenticateUser()
            }

            let signer = try await loadSigner(for: wallet)

            let (stakeTx, tipTx, txFees) = try await transactionBuilder.buildStake(
                signer: signer,
                outputLstMint: selectedLST.mint,
                amount: amountLamports
            )
            self.fees = txFees

            let bundleId = try await transactionBuilder.submitStakeViaJito(
                stakeTransaction: stakeTx,
                tipTransaction: tipTx
            )
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
        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Approve staking signing")
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
