import Foundation
import SwiftUI
import DeadboltCore

/// Unified send view model that handles both SOL and SPL token transfers
/// on a single page with editing -> reviewing -> confirming phases.
@MainActor
final class UnifiedSendViewModel: ObservableObject {
    enum Phase {
        case editing
        case reviewing
        case confirming
    }

    /// Represents what to send: SOL or a specific SPL token.
    enum SendToken: Equatable {
        case sol
        case token(TokenBalance)

        var name: String {
            switch self {
            case .sol: return "SOL"
            case .token(let tb): return tb.definition.name
            }
        }

        var decimals: Int {
            switch self {
            case .sol: return 9
            case .token(let tb): return tb.definition.decimals
            }
        }

        static func == (lhs: SendToken, rhs: SendToken) -> Bool {
            switch (lhs, rhs) {
            case (.sol, .sol): return true
            case (.token(let a), .token(let b)): return a.id == b.id
            default: return false
            }
        }
    }

    @Published var phase: Phase = .editing
    @Published var selectedToken: SendToken = .sol
    @Published var recipientAddress: String = ""
    @Published var recipientValid: Bool = false
    @Published var amountString: String = ""
    @Published var fees: TransactionFees?
    @Published var simulationStatus: TransactionPreviewView.SimulationStatus = .pending
    @Published var errorMessage: String?

    let confirmationTracker: ConfirmationTracker
    let signerLoader: SignerLoader

    private let walletService: WalletService
    private let authService: AuthService
    private let transactionBuilder: TransactionBuilder
    private let rpcClient: SolanaRPCClient

    init(walletService: WalletService, authService: AuthService) {
        self.walletService = walletService
        self.authService = authService
        let rpcURL = AppConfig.defaultRPCURL
        self.rpcClient = SolanaRPCClient(rpcURL: rpcURL)
        self.transactionBuilder = TransactionBuilder(rpcClient: rpcClient)
        self.confirmationTracker = ConfirmationTracker(rpcClient: rpcClient)
        self.signerLoader = SignerLoader(walletService: walletService)
    }

    // MARK: - Computed Properties

    var amountValue: Double { Double(amountString) ?? 0 }

    var amountLamports: UInt64 {
        guard let decimal = Decimal(string: amountString), decimal > 0 else { return 0 }
        let lamports = decimal * 1_000_000_000
        return NSDecimalNumber(decimal: lamports).uint64Value
    }

    var amountRaw: UInt64 {
        guard case .token(let tb) = selectedToken else { return amountLamports }
        guard let decimal = Decimal(string: amountString), decimal > 0 else { return 0 }
        var multiplier = Decimal(1)
        for _ in 0..<tb.definition.decimals { multiplier *= 10 }
        let raw = decimal * multiplier
        return NSDecimalNumber(decimal: raw).uint64Value
    }

    var maxAmount: Double {
        switch selectedToken {
        case .sol:
            let balance = Double(walletService.solBalance) / 1_000_000_000.0
            return max(0, balance - 0.001)
        case .token(let tb):
            return tb.uiAmount
        }
    }

    var canReview: Bool {
        recipientValid && amountValue > 0 && amountValue <= maxAmount
    }

    var actionDescription: String {
        switch selectedToken {
        case .sol:
            return "Send \(DashboardViewModel.formatTokenAmount(amountValue)) SOL"
        case .token(let tb):
            return "Send \(DashboardViewModel.formatTokenAmount(amountValue)) \(tb.definition.name)"
        }
    }

    // MARK: - Phase Navigation

    func review() {
        phase = .reviewing
        simulateTransaction()
    }

    func edit() {
        phase = .editing
        errorMessage = nil
    }

    // MARK: - Transaction

    func approve() async {
        guard let wallet = walletService.activeWallet else {
            errorMessage = "No wallet selected"
            return
        }

        if case .failed = simulationStatus {
            errorMessage = "Transaction simulation failed. Cannot submit."
            return
        }

        phase = .confirming
        errorMessage = nil
        signerLoader.clearPrompt()

        do {
            // Require auth for hot wallets
            if !signerLoader.isHardwareWallet {
                guard await authService.authenticate(reason: "Approve transaction signing") else {
                    errorMessage = "Authentication required"
                    phase = .reviewing
                    return
                }
            }

            if signerLoader.isHardwareWallet {
                signerLoader.hardwareWalletPrompt = "Preparing transaction for hardware signing..."
            }

            let signer = try await signerLoader.loadSigner(for: wallet)
            let recipient = try SolanaPublicKey(base58: recipientAddress)

            switch selectedToken {
            case .sol:
                try await submitSendSOL(signer: signer, recipient: recipient, wallet: wallet)
            case .token(let tb):
                try await submitSendToken(signer: signer, recipient: recipient, token: tb)
            }
        } catch {
            signerLoader.clearPrompt()
            errorMessage = error.localizedDescription
        }
    }

    private func submitSendSOL(signer: TransactionSigner, recipient: SolanaPublicKey, wallet: Wallet) async throws {
        let tip: UInt64 = AppConfig.defaultNetwork == .mainnet ? JitoTip.defaultTipLamports : 0
        let (transaction, txFees) = try await transactionBuilder.buildSendSOL(
            from: signer,
            to: recipient,
            lamports: amountLamports,
            tipLamports: tip
        )
        self.fees = txFees
        signerLoader.clearPrompt()

        let signature: String
        if AppConfig.defaultNetwork == .mainnet {
            signature = try await transactionBuilder.submitViaJito(transaction: transaction)
        } else {
            signature = try await transactionBuilder.submitViaRPC(transaction: transaction)
        }

        await confirmationTracker.track(signature: signature)
    }

    private func submitSendToken(signer: TransactionSigner, recipient: SolanaPublicKey, token: TokenBalance) async throws {
        let mint = try SolanaPublicKey(base58: token.definition.mint)
        let (transaction, txFees) = try await transactionBuilder.buildSendToken(
            from: signer,
            to: recipient,
            mint: mint,
            amount: amountRaw,
            decimals: UInt8(token.definition.decimals)
        )
        self.fees = txFees
        signerLoader.clearPrompt()

        let signature = try await transactionBuilder.submitViaJito(transaction: transaction)
        await confirmationTracker.track(signature: signature)
    }

    // MARK: - Simulation

    private func simulateTransaction() {
        simulationStatus = .pending

        if signerLoader.isHardwareWallet {
            let tip: UInt64 = AppConfig.defaultNetwork == .mainnet ? JitoTip.defaultTipLamports : 0
            fees = TransactionFees(baseFee: 5000, priorityFee: 0, tipAmount: tip)
            simulationStatus = .skipped
            return
        }

        Task {
            do {
                guard let wallet = walletService.activeWallet else { return }
                let signer = try await signerLoader.loadSigner(for: wallet)
                let recipient = try SolanaPublicKey(base58: recipientAddress)

                switch selectedToken {
                case .sol:
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

                case .token(let tb):
                    let mint = try SolanaPublicKey(base58: tb.definition.mint)
                    let (transaction, txFees) = try await transactionBuilder.buildSendToken(
                        from: signer,
                        to: recipient,
                        mint: mint,
                        amount: amountRaw,
                        decimals: UInt8(tb.definition.decimals)
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
                }
            } catch {
                simulationStatus = .failed(error: error.localizedDescription)
            }
        }
    }
}
