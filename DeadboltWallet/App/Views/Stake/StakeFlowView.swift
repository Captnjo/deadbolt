import SwiftUI
import DeadboltCore

/// P5-010: Full staking flow replacing the stub.
/// Steps: input (amount + LST select) -> quote -> preview -> confirm.
struct StakeFlowView: View {
    @EnvironmentObject var walletService: WalletService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: StakeViewModel

    init(walletService: WalletService) {
        _viewModel = StateObject(wrappedValue: StakeViewModel(walletService: walletService))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Button {
                    if viewModel.step == .input {
                        dismiss()
                    } else {
                        viewModel.goBack()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text(stepTitle)
                    .font(.headline)

                Spacer()

                Color.clear.frame(width: 24)
            }
            .padding()

            Divider()

            Group {
                switch viewModel.step {
                case .input:
                    inputStep
                case .quote:
                    quoteStep
                case .preview:
                    previewStep
                case .confirming:
                    confirmingStep
                }
            }
            .padding()

            if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error)
                        .font(.caption)
                }
                .foregroundStyle(.red)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 450, minHeight: 450)
    }

    private var stepTitle: String {
        switch viewModel.step {
        case .input: return "Stake SOL"
        case .quote: return "Stake -- Quote"
        case .preview: return "Stake -- Preview"
        case .confirming: return "Stake -- Confirming"
        }
    }

    // MARK: - Step 1: Input

    private var inputStep: some View {
        VStack(spacing: 20) {
            StakeInputView(
                amountString: $viewModel.amountString,
                selectedLST: $viewModel.selectedLST,
                solBalance: walletService.solBalance,
                solPrice: walletService.solPrice
            )

            Spacer()

            Button("Get Quote") {
                viewModel.fetchQuote()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canGetQuote)
        }
    }

    // MARK: - Step 2: Quote

    private var quoteStep: some View {
        VStack(spacing: 16) {
            if let quote = viewModel.sanctumQuote {
                StakeQuoteView(
                    quote: quote,
                    lstName: viewModel.selectedLST.name,
                    solAmount: viewModel.amountSOL
                )
            } else if viewModel.isQuoting {
                Spacer()
                ProgressView("Getting quote...")
                Spacer()
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Back") {
                    viewModel.goBack()
                }
                .buttonStyle(.bordered)

                Button("Review Stake") {
                    viewModel.proceedToPreview()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.sanctumQuote == nil)
            }
        }
    }

    // MARK: - Step 3: Preview

    private var previewStep: some View {
        VStack(spacing: 20) {
            if let quote = viewModel.sanctumQuote {
                let outAmount = (Double(quote.outAmount) ?? 0) / 1_000_000_000.0
                UnifiedTransactionPreviewView(preview: TransactionPreview(
                    actionDescription: "Stake \(DashboardViewModel.formatTokenAmount(viewModel.amountSOL)) SOL for ~\(DashboardViewModel.formatTokenAmount(outAmount)) \(viewModel.selectedLST.name)",
                    balanceChanges: [],
                    feeBreakdown: viewModel.fees ?? TransactionFees(baseFee: 10000, priorityFee: 0, tipAmount: 10000),
                    simulationStatus: .pending,
                    warnings: []
                ))
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel") {
                    viewModel.goBack()
                }
                .buttonStyle(.bordered)

                Button("Approve & Stake") {
                    Task { await viewModel.approve() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Step 4: Confirming

    private var confirmingStep: some View {
        VStack(spacing: 20) {
            ConfirmationView(tracker: viewModel.confirmationTracker)

            Spacer()

            if case .finalized = viewModel.confirmationTracker.status {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            } else if case .failed = viewModel.confirmationTracker.status {
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
