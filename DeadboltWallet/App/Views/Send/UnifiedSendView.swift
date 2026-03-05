import SwiftUI
import DeadboltCore

/// Single-page send view that handles both SOL and SPL token transfers.
/// All inputs are on one screen; review and confirmation appear inline.
struct UnifiedSendView: View {
    @EnvironmentObject var walletService: WalletService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: UnifiedSendViewModel

    init(walletService: WalletService, authService: AuthService) {
        _viewModel = StateObject(wrappedValue: UnifiedSendViewModel(
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

                Text("Send")
                    .font(.headline)

                Spacer()

                Color.clear.frame(width: 24)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Token Selector
                    tokenSelector
                        .opacity(isEditing ? 1.0 : 0.6)
                        .allowsHitTesting(isEditing)

                    // MARK: - Recipient
                    RecipientPickerView(
                        recipientAddress: $viewModel.recipientAddress,
                        isValid: $viewModel.recipientValid
                    )
                    .opacity(isEditing ? 1.0 : 0.6)
                    .allowsHitTesting(isEditing)

                    // MARK: - Amount
                    amountSection
                        .opacity(isEditing ? 1.0 : 0.6)
                        .allowsHitTesting(isEditing)

                    // MARK: - Review Button (editing only)
                    if isEditing {
                        Button("Review Send") {
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
                            fees: viewModel.fees,
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
        .frame(minWidth: 450, minHeight: 450)
        .animation(.spring(duration: 0.35), value: viewModel.phase)
    }

    // MARK: - Token Selector

    @State private var showingTokenPicker = false

    private var tokenSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token")
                .font(.headline)

            Button {
                showingTokenPicker = true
            } label: {
                HStack {
                    Text(viewModel.selectedToken.name)
                        .fontWeight(.medium)
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
            .popover(isPresented: $showingTokenPicker) {
                tokenPickerContent
                    .frame(width: 300, height: 400)
            }
        }
    }

    private var tokenPickerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Token")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            ScrollView {
                VStack(spacing: 0) {
                    // SOL option
                    Button {
                        viewModel.selectedToken = .sol
                        viewModel.amountString = ""
                        showingTokenPicker = false
                    } label: {
                        HStack {
                            Text("SOL")
                                .fontWeight(.medium)
                            Spacer()
                            Text(DashboardViewModel.formatSOL(walletService.solBalance))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()

                    // SPL token options
                    ForEach(walletService.tokenBalances) { token in
                        Button {
                            viewModel.selectedToken = .token(token)
                            viewModel.amountString = ""
                            showingTokenPicker = false
                        } label: {
                            HStack {
                                Text(token.definition.name)
                                    .fontWeight(.medium)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(DashboardViewModel.formatTokenAmount(token.uiAmount))
                                        .monospacedDigit()
                                    if token.usdValue > 0 {
                                        Text(DashboardViewModel.formatUSD(token.usdValue))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
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

    // MARK: - Amount Section

    private var amountSection: some View {
        Group {
            switch viewModel.selectedToken {
            case .sol:
                AmountEntryView(
                    amountString: $viewModel.amountString,
                    balanceLamports: walletService.solBalance,
                    solPrice: walletService.solPrice
                )
            case .token(let tb):
                TokenAmountEntryView(
                    amountString: $viewModel.amountString,
                    token: tb,
                    solPrice: walletService.solPrice
                )
            }
        }
    }
}
