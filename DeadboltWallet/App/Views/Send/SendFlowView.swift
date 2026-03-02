import SwiftUI
import DeadboltCore

struct SendFlowView: View {
    @EnvironmentObject var walletService: WalletService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SendViewModel

    init(walletService: WalletService, authService: AuthService) {
        _viewModel = StateObject(wrappedValue: SendViewModel(walletService: walletService, authService: authService))
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

                // Balance spacer
                Color.clear.frame(width: 24)
            }
            .padding()

            Divider()

            // Step content
            Group {
                switch viewModel.step {
                case .recipient:
                    recipientStep
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
        case .recipient: return "Send SOL — Recipient"
        case .amount: return "Send SOL — Amount"
        case .preview: return "Send SOL — Preview"
        case .confirming: return "Send SOL — Confirming"
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
                viewModel.proceedToAmount()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canProceedToAmount)
        }
    }

    // MARK: - Step 2: Amount

    private var amountStep: some View {
        VStack(spacing: 20) {
            AmountEntryView(
                amountString: $viewModel.amountString,
                balanceLamports: walletService.solBalance,
                solPrice: walletService.solPrice
            )

            Spacer()

            Button("Preview Transaction") {
                viewModel.proceedToPreview()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canProceedToPreview)
        }
    }

    // MARK: - Step 3: Preview

    private var previewStep: some View {
        VStack(spacing: 20) {
            if let fees = viewModel.fees {
                TransactionPreviewView(
                    recipientAddress: viewModel.recipientAddress,
                    amountSOL: viewModel.amountSOL,
                    fees: fees,
                    simulationStatus: viewModel.simulationStatus
                )
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

    // MARK: - Step 4: Confirming

    private var confirmingStep: some View {
        VStack(spacing: 20) {
            if let prompt = viewModel.hardwareWalletPrompt {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .symbolEffect(.pulse)
                    Text(prompt)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.orange)
                .padding()
                .background(.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

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
