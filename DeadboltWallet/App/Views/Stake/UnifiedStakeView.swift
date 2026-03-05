import SwiftUI
import DeadboltCore

/// Single-page stake view with live debounced quotes.
/// Amount entry and LST selector visible on one screen; review slides up inline.
struct UnifiedStakeView: View {
    @EnvironmentObject var walletService: WalletService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: UnifiedStakeViewModel

    init(walletService: WalletService, authService: AuthService) {
        _viewModel = StateObject(wrappedValue: UnifiedStakeViewModel(
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

                Text("Stake")
                    .font(.headline)

                Spacer()

                Color.clear.frame(width: 24)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Amount + LST Input
                    stakeInputSection
                        .opacity(isEditing ? 1.0 : 0.6)
                        .allowsHitTesting(isEditing)

                    // MARK: - Live Quote
                    if viewModel.sanctumQuote != nil {
                        StakeQuoteView(
                            quote: viewModel.sanctumQuote!,
                            lstName: viewModel.selectedLST.name,
                            solAmount: viewModel.amountSOL
                        )
                        .opacity(isEditing ? 1.0 : 0.6)
                    }

                    // MARK: - Quoting Indicator
                    if viewModel.isQuoting && viewModel.sanctumQuote == nil {
                        ProgressView("Getting quote...")
                            .padding()
                    }

                    // MARK: - Review Button
                    if isEditing {
                        Button("Review Stake") {
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
                            fees: viewModel.fees ?? TransactionFees(baseFee: 10000, priorityFee: 0, tipAmount: 10000),
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

    // MARK: - Stake Input Section

    private var stakeInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // SOL Amount
            VStack(alignment: .leading, spacing: 8) {
                Text("Stake SOL")
                    .font(.headline)

                HStack {
                    TextField("0.0", text: $viewModel.amountString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.title3, design: .monospaced))
                        .onChange(of: viewModel.amountString) { _, _ in
                            viewModel.onInputChanged()
                        }

                    Text("SOL")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Button("Max") {
                        var result = String(format: "%.9f", viewModel.maxSOL)
                        while result.hasSuffix("0") { result.removeLast() }
                        if result.hasSuffix(".") { result.removeLast() }
                        viewModel.amountString = result
                        viewModel.onInputChanged()
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Text("Balance: \(DashboardViewModel.formatSOL(walletService.solBalance)) SOL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if walletService.solPrice > 0 && viewModel.amountSOL > 0 {
                        Text(DashboardViewModel.formatUSD(viewModel.amountSOL * walletService.solPrice))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.amountSOL > viewModel.maxSOL && viewModel.amountSOL > 0 {
                    Text("Insufficient balance")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Divider()

            // LST Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Stake Into")
                    .font(.headline)

                ForEach(LSTOption.allCases, id: \.self) { lst in
                    Button {
                        viewModel.selectedLST = lst
                        viewModel.onInputChanged()
                    } label: {
                        HStack {
                            Image(systemName: viewModel.selectedLST == lst ? "circle.inset.filled" : "circle")
                                .foregroundStyle(viewModel.selectedLST == lst ? .blue : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(lst.name)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                Text(lst.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(viewModel.selectedLST == lst ? Color.blue.opacity(0.1) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
