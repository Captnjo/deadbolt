import SwiftUI
import DeadboltCore

/// P3-011: Full flow for sending SPL tokens.
/// Steps: recipient -> token select -> amount -> preview -> confirm.
struct SendTokenFlowView: View {
    @EnvironmentObject var walletService: WalletService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SendTokenViewModel

    init(walletService: WalletService, authService: AuthService) {
        _viewModel = StateObject(wrappedValue: SendTokenViewModel(walletService: walletService, authService: authService))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Button {
                    if viewModel.step == .recipient {
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

            // Step content
            Group {
                switch viewModel.step {
                case .recipient:
                    recipientStep
                case .tokenSelect:
                    tokenSelectStep
                case .amount:
                    amountStep
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
        .frame(minWidth: 450, minHeight: 400)
    }

    private var stepTitle: String {
        switch viewModel.step {
        case .recipient: return "Send Token -- Recipient"
        case .tokenSelect: return "Send Token -- Select Token"
        case .amount: return "Send Token -- Amount"
        case .preview: return "Send Token -- Preview"
        case .confirming: return "Send Token -- Confirming"
        }
    }

    // MARK: - Step 1: Recipient

    private var recipientStep: some View {
        VStack(spacing: 20) {
            RecipientPickerView(
                recipientAddress: $viewModel.recipientAddress,
                isValid: $viewModel.recipientValid
            )

            Spacer()

            Button("Next") {
                viewModel.proceedToTokenSelect()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canProceedToTokenSelect)
        }
    }

    // MARK: - Step 2: Token Select

    private var tokenSelectStep: some View {
        TokenSelectorView(
            tokenBalances: walletService.tokenBalances,
            onSelect: { token in
                viewModel.selectToken(token)
            }
        )
    }

    // MARK: - Step 3: Amount

    private var amountStep: some View {
        VStack(spacing: 20) {
            if let token = viewModel.selectedToken {
                TokenAmountEntryView(
                    amountString: $viewModel.amountString,
                    token: token,
                    solPrice: walletService.solPrice
                )
            }

            Spacer()

            Button("Preview Transaction") {
                viewModel.proceedToPreview()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canProceedToPreview)
        }
    }

    // MARK: - Step 4: Preview

    private var previewStep: some View {
        VStack(spacing: 20) {
            if let fees = viewModel.fees, let token = viewModel.selectedToken {
                UnifiedTransactionPreviewView(preview: TransactionPreview(
                    actionDescription: "Send \(DashboardViewModel.formatTokenAmount(viewModel.amountToken)) \(token.definition.name)",
                    balanceChanges: [],
                    feeBreakdown: fees,
                    simulationStatus: mapSimulationStatus(viewModel.simulationStatus),
                    warnings: []
                ))
            } else {
                ProgressView("Building transaction...")
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel") {
                    viewModel.goBack()
                }
                .buttonStyle(.bordered)

                Button("Approve & Send") {
                    Task { await viewModel.approve() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.fees == nil)
            }
        }
    }

    // MARK: - Step 5: Confirming

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

    private func mapSimulationStatus(_ status: TransactionPreviewView.SimulationStatus) -> SimulationStatus {
        switch status {
        case .pending: return .pending
        case .success(let cu): return .success(unitsConsumed: cu)
        case .failed(let error): return .failure(error: error)
        case .skipped: return .pending
        }
    }
}
