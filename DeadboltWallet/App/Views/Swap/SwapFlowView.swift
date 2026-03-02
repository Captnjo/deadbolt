import SwiftUI
import DeadboltCore

/// P4-013: Full swap flow replacing the stub.
/// Steps: input select -> output select -> quote -> preview -> confirm.
struct SwapFlowView: View {
    @EnvironmentObject var walletService: WalletService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SwapViewModel

    init(walletService: WalletService, authService: AuthService) {
        _viewModel = StateObject(wrappedValue: SwapViewModel(walletService: walletService, authService: authService))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Button {
                    if viewModel.step == .inputSelect {
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
                case .inputSelect:
                    inputSelectStep
                case .outputSelect:
                    outputSelectStep
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
        case .inputSelect: return "Swap -- Select Input"
        case .outputSelect: return "Swap -- Select Output"
        case .quote: return "Swap -- Quote"
        case .preview: return "Swap -- Preview"
        case .confirming: return "Swap -- Confirming"
        }
    }

    // MARK: - Step 1: Input Selection

    private var inputSelectStep: some View {
        VStack(spacing: 16) {
            SwapInputView(
                selectedToken: $viewModel.inputToken,
                amountString: $viewModel.amountString,
                solBalance: walletService.solBalance,
                tokenBalances: walletService.tokenBalances,
                solPrice: walletService.solPrice
            )

            Spacer()

            Button("Next") {
                if let token = viewModel.inputToken {
                    viewModel.selectInput(token)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.inputToken == nil || viewModel.inputAmountRaw == 0)
        }
    }

    // MARK: - Step 2: Output Selection

    private var outputSelectStep: some View {
        SwapOutputView(
            onSelect: { token in
                viewModel.selectOutput(token)
                viewModel.fetchQuote()
            },
            tokenBalances: walletService.tokenBalances
        )
    }

    // MARK: - Step 3: Quote Display

    private var quoteStep: some View {
        VStack(spacing: 16) {
            // Aggregator toggle
            Picker("Aggregator", selection: Binding(
                get: { viewModel.aggregator },
                set: { viewModel.switchAggregator(to: $0) }
            )) {
                Text("DFlow").tag(SwapViewModel.SwapAggregator.dflow)
                Text("Jupiter").tag(SwapViewModel.SwapAggregator.jupiter)
            }
            .pickerStyle(.segmented)

            // Quote display
            switch viewModel.aggregator {
            case .jupiter:
                if let quote = viewModel.jupiterQuote {
                    SwapQuoteView(
                        quote: quote,
                        inputTokenName: viewModel.inputToken?.name ?? "?",
                        outputTokenName: viewModel.outputToken?.name ?? "?",
                        inputDecimals: viewModel.inputToken?.decimals ?? 9,
                        outputDecimals: viewModel.outputToken?.decimals ?? 9,
                        isRefreshing: viewModel.isQuoting,
                        aggregatorName: "Jupiter",
                        onRefresh: { viewModel.refreshQuote() }
                    )
                } else if viewModel.isQuoting {
                    Spacer()
                    ProgressView("Getting quote...")
                    Spacer()
                }
            case .dflow:
                if viewModel.dflowOrder != nil {
                    DFlowQuoteView(
                        inputTokenName: viewModel.inputToken?.name ?? "?",
                        outputTokenName: viewModel.outputToken?.name ?? "?",
                        inputAmount: viewModel.amountString,
                        isRefreshing: viewModel.isQuoting,
                        onRefresh: { viewModel.refreshQuote() }
                    )
                } else if viewModel.isQuoting {
                    Spacer()
                    ProgressView("Getting quote...")
                    Spacer()
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel") {
                    viewModel.goBack()
                }
                .buttonStyle(.bordered)

                Button("Review Swap") {
                    viewModel.proceedToPreview()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasQuote)
            }
        }
    }

    // MARK: - Step 4: Preview

    private var previewStep: some View {
        VStack(spacing: 20) {
            switch viewModel.aggregator {
            case .jupiter:
                if let quote = viewModel.jupiterQuote {
                    let inputAmt = (Double(quote.inAmount) ?? 0) / pow(10.0, Double(viewModel.inputToken?.decimals ?? 9))
                    let outputAmt = (Double(quote.outAmount) ?? 0) / pow(10.0, Double(viewModel.outputToken?.decimals ?? 9))

                    UnifiedTransactionPreviewView(preview: TransactionPreview(
                        actionDescription: "Swap \(DashboardViewModel.formatTokenAmount(inputAmt)) \(viewModel.inputToken?.name ?? "?") for ~\(DashboardViewModel.formatTokenAmount(outputAmt)) \(viewModel.outputToken?.name ?? "?") via Jupiter",
                        balanceChanges: [],
                        feeBreakdown: viewModel.fees ?? TransactionFees(baseFee: 5000, priorityFee: 0, tipAmount: 10000),
                        simulationStatus: .pending,
                        warnings: []
                    ))
                }
            case .dflow:
                if viewModel.dflowOrder != nil {
                    UnifiedTransactionPreviewView(preview: TransactionPreview(
                        actionDescription: "Swap \(viewModel.amountString) \(viewModel.inputToken?.name ?? "?") for \(viewModel.outputToken?.name ?? "?") via DFlow",
                        balanceChanges: [],
                        feeBreakdown: viewModel.fees ?? TransactionFees(baseFee: 5000, priorityFee: 0, tipAmount: 0),
                        simulationStatus: .pending,
                        warnings: []
                    ))
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel") {
                    viewModel.goBack()
                }
                .buttonStyle(.bordered)

                Button("Approve & Swap") {
                    Task { await viewModel.approve() }
                }
                .buttonStyle(.borderedProminent)
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
}
