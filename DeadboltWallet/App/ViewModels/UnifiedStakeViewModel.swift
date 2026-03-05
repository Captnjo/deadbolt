import Foundation
import SwiftUI
import DeadboltCore
#if os(macOS)
import HardwareWallet
#endif

/// Unified stake view model with single-page layout.
/// Amount and LST selector on one page. Quote fetches live on changes.
@MainActor
final class UnifiedStakeViewModel: ObservableObject {
    enum Phase {
        case editing
        case reviewing
        case confirming
    }

    @Published var phase: Phase = .editing
    @Published var amountString: String = ""
    @Published var selectedLST: LSTOption = .jitoSOL
    @Published var sanctumQuote: SanctumQuote?
    @Published var fees: TransactionFees?
    @Published var isQuoting: Bool = false
    @Published var errorMessage: String?
    @Published var simulationStatus: TransactionPreviewView.SimulationStatus = .pending

    let confirmationTracker: ConfirmationTracker
    let signerLoader: SignerLoader

    private let walletService: WalletService
    private let authService: AuthService
    private let transactionBuilder: TransactionBuilder
    private let sanctumClient: SanctumClient
    private let rpcClient: SolanaRPCClient
    private var debounceTask: Task<Void, Never>?

    init(walletService: WalletService, authService: AuthService) {
        self.walletService = walletService
        self.authService = authService
        let rpcURL = AppConfig.defaultRPCURL
        self.rpcClient = SolanaRPCClient(rpcURL: rpcURL)
        self.transactionBuilder = TransactionBuilder(rpcClient: rpcClient)
        self.sanctumClient = SanctumClient()
        self.confirmationTracker = ConfirmationTracker(rpcClient: rpcClient)
        self.signerLoader = SignerLoader(walletService: walletService)
    }

    // MARK: - Computed Properties

    var amountSOL: Double { Double(amountString) ?? 0 }

    var amountLamports: UInt64 {
        guard let decimal = Decimal(string: amountString), decimal > 0 else { return 0 }
        let lamports = decimal * 1_000_000_000
        return NSDecimalNumber(decimal: lamports).uint64Value
    }

    var maxSOL: Double {
        let balance = Double(walletService.solBalance) / 1_000_000_000.0
        return max(0, balance - 0.01)
    }

    var canReview: Bool {
        amountSOL > 0 && amountSOL <= maxSOL && sanctumQuote != nil
    }

    var actionDescription: String {
        if let quote = sanctumQuote {
            let outAmount = (Double(quote.outAmount) ?? 0) / 1_000_000_000.0
            return "Stake \(DashboardViewModel.formatTokenAmount(amountSOL)) SOL for ~\(DashboardViewModel.formatTokenAmount(outAmount)) \(selectedLST.name)"
        }
        return "Stake \(DashboardViewModel.formatTokenAmount(amountSOL)) SOL for \(selectedLST.name)"
    }

    // MARK: - Phase Navigation

    func review() {
        phase = .reviewing
        simulationStatus = .skipped
    }

    func edit() {
        phase = .editing
        errorMessage = nil
    }

    // MARK: - Debounced Quoting

    /// Called when amount or LST selection changes.
    func onInputChanged() {
        debounceTask?.cancel()
        guard amountLamports > 0 else {
            sanctumQuote = nil
            return
        }

        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            if Task.isCancelled { return }
            fetchQuote()
        }
    }

    private func fetchQuote() {
        guard amountLamports > 0 else {
            errorMessage = "Enter an amount"
            return
        }

        isQuoting = true
        errorMessage = nil

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

    // MARK: - Approve & Submit

    func approve() async {
        guard let wallet = walletService.activeWallet else {
            errorMessage = "No wallet selected"
            return
        }

        phase = .confirming
        errorMessage = nil
        signerLoader.clearPrompt()

        do {
            if !signerLoader.isHardwareWallet {
                guard await authService.authenticate(reason: "Approve staking signing") else {
                    errorMessage = "Authentication required"
                    phase = .reviewing
                    return
                }
            }

            if signerLoader.isHardwareWallet {
                signerLoader.hardwareWalletPrompt = "Preparing transaction for hardware signing..."
            }

            let signer = try await signerLoader.loadSigner(for: wallet)

            let (stakeTx, tipTx, txFees) = try await transactionBuilder.buildStake(
                signer: signer,
                outputLstMint: selectedLST.mint,
                amount: amountLamports
            )
            self.fees = txFees
            signerLoader.clearPrompt()

            let bundleId = try await transactionBuilder.submitStakeViaJito(
                stakeTransaction: stakeTx,
                tipTransaction: tipTx
            )
            await confirmationTracker.trackBundle(bundleId: bundleId)
        } catch {
            signerLoader.clearPrompt()
            errorMessage = error.localizedDescription
        }
    }

    deinit {
        debounceTask?.cancel()
    }
}
