import SwiftUI
import DeadboltCore

/// Single-page swap view with live debounced quotes.
/// Both token selectors and amount visible at once. Review slides up inline.
struct UnifiedSwapView: View {
    @EnvironmentObject var walletService: WalletService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: UnifiedSwapViewModel

    init(walletService: WalletService, authService: AuthService) {
        _viewModel = StateObject(wrappedValue: UnifiedSwapViewModel(
            walletService: walletService,
            authService: authService
        ))
    }

    private var isEditing: Bool { viewModel.phase == .editing }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Swap")
                    .font(.headline)

                Spacer()

                Color.clear.frame(width: 24)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Aggregator Toggle
                    Picker("Aggregator", selection: Binding(
                        get: { viewModel.aggregator },
                        set: { viewModel.switchAggregator(to: $0) }
                    )) {
                        Text("DFlow").tag(UnifiedSwapViewModel.SwapAggregator.dflow)
                        Text("Jupiter").tag(UnifiedSwapViewModel.SwapAggregator.jupiter)
                    }
                    .pickerStyle(.segmented)
                    .opacity(isEditing ? 1.0 : 0.6)
                    .allowsHitTesting(isEditing)

                    // MARK: - You Pay
                    youPaySection
                        .opacity(isEditing ? 1.0 : 0.6)
                        .allowsHitTesting(isEditing)

                    // MARK: - Swap Direction
                    Button {
                        viewModel.swapDirection()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEditing)
                    .opacity(isEditing ? 1.0 : 0.6)

                    // MARK: - You Receive
                    youReceiveSection
                        .opacity(isEditing ? 1.0 : 0.6)
                        .allowsHitTesting(isEditing)

                    // MARK: - Live Quote Details
                    if viewModel.hasQuote {
                        quoteDetailsSection
                            .opacity(isEditing ? 1.0 : 0.6)
                    }

                    // MARK: - Quoting Indicator
                    if viewModel.isQuoting && !viewModel.hasQuote {
                        ProgressView("Getting quote...")
                            .padding()
                    }

                    // MARK: - Review Button
                    if isEditing {
                        Button("Review Swap") {
                            withAnimation(.spring(duration: 0.35)) {
                                viewModel.review()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canReview)
                        .frame(maxWidth: .infinity)
                    }

                    // MARK: - Inline Review Section
                    if viewModel.phase != .editing {
                        InlineReviewSection(
                            fees: viewModel.fees ?? TransactionFees(baseFee: 5000, priorityFee: 0, tipAmount: viewModel.aggregator == .jupiter ? 10000 : 0),
                            simulationStatus: viewModel.simulationStatus,
                            actionDescription: viewModel.actionDescription,
                            confirmationTracker: viewModel.confirmationTracker,
                            signerLoader: viewModel.signerLoader,
                            onConfirm: {
                                Task { await viewModel.approve() }
                            },
                            onEdit: {
                                withAnimation(.spring(duration: 0.35)) {
                                    viewModel.edit()
                                }
                            },
                            onDone: {
                                dismiss()
                            },
                            isConfirming: viewModel.phase == .confirming
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // MARK: - Error
                    if let error = viewModel.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                            Text(error)
                                .font(.caption)
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 450, minHeight: 500)
        .animation(.spring(duration: 0.35), value: viewModel.phase)
    }

    // MARK: - You Pay Section

    @State private var showingInputPicker = false

    private var youPaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You Pay")
                .font(.headline)

            // Token selector
            Button {
                showingInputPicker = true
            } label: {
                HStack {
                    Text(viewModel.inputToken?.name ?? "Select token")
                        .fontWeight(.medium)
                        .foregroundStyle(viewModel.inputToken == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingInputPicker) {
                inputTokenPicker
                    .frame(width: 300, height: 400)
            }

            // Amount entry
            HStack {
                TextField("0.0", text: $viewModel.amountString)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.title3, design: .monospaced))
                    .onChange(of: viewModel.amountString) { _, _ in
                        viewModel.onInputChanged()
                    }

                if viewModel.inputToken != nil {
                    Button("Max") {
                        viewModel.amountString = formatMaxAmount()
                        viewModel.onInputChanged()
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Balance
            if let token = viewModel.inputToken {
                HStack {
                    Text("Balance: \(inputBalance(token))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private var inputTokenPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Input Token")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            ScrollView {
                VStack(spacing: 0) {
                    Button {
                        viewModel.inputToken = .sol
                        viewModel.amountString = ""
                        viewModel.onInputChanged()
                        showingInputPicker = false
                    } label: {
                        HStack {
                            Text("SOL").fontWeight(.medium)
                            Spacer()
                            Text(DashboardViewModel.formatSOL(walletService.solBalance)).monospacedDigit()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()

                    ForEach(walletService.tokenBalances) { token in
                        Button {
                            viewModel.inputToken = .token(token)
                            viewModel.amountString = ""
                            viewModel.onInputChanged()
                            showingInputPicker = false
                        } label: {
                            HStack {
                                Text(token.definition.name).fontWeight(.medium)
                                Spacer()
                                Text(DashboardViewModel.formatTokenAmount(token.uiAmount)).monospacedDigit()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if token.id != walletService.tokenBalances.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - You Receive Section

    @State private var showingOutputPicker = false

    private var youReceiveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You Receive")
                .font(.headline)

            // Output token selector
            Button {
                showingOutputPicker = true
            } label: {
                HStack {
                    Text(viewModel.outputToken?.name ?? "Select token")
                        .fontWeight(.medium)
                        .foregroundStyle(viewModel.outputToken == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingOutputPicker) {
                outputTokenPicker
                    .frame(width: 300, height: 400)
            }

            // Estimated output amount (read-only)
            if viewModel.hasQuote {
                HStack {
                    Text(viewModel.outputAmountDisplay)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if viewModel.isQuoting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var outputTokenPicker: some View {
        SwapOutputView(
            onSelect: { token in
                viewModel.outputToken = token
                viewModel.onInputChanged()
                showingOutputPicker = false
            },
            tokenBalances: walletService.tokenBalances
        )
    }

    // MARK: - Quote Details

    private var quoteDetailsSection: some View {
        Group {
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
                }
            }
        }
    }

    // MARK: - Helpers

    private func inputBalance(_ token: SwapToken) -> String {
        switch token {
        case .sol:
            return DashboardViewModel.formatSOL(walletService.solBalance) + " SOL"
        case .token(let tb):
            return DashboardViewModel.formatTokenAmount(tb.uiAmount) + " " + tb.definition.name
        }
    }

    private func formatMaxAmount() -> String {
        guard let token = viewModel.inputToken else { return "0" }
        let amount: Double
        switch token {
        case .sol:
            amount = max(0, Double(walletService.solBalance) / 1_000_000_000.0 - 0.01)
        case .token(let tb):
            amount = tb.uiAmount
        }
        var result = String(format: "%.9f", amount)
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }
}
