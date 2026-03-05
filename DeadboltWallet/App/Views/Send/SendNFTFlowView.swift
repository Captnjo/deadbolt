import SwiftUI
import DeadboltCore

/// P3-011: Full flow for sending NFTs.
/// Steps: recipient -> NFT select -> preview -> confirm.
struct SendNFTFlowView: View {
    @EnvironmentObject var walletService: WalletService
    @Environment(\.dismiss) private var dismiss

    enum Step {
        case recipient
        case nftSelect
        case preview
        case confirming
    }

    @State private var step: Step = .recipient
    @State private var recipientAddress: String = ""
    @State private var recipientValid: Bool = false
    @State private var selectedNFT: NFTAsset?
    @State private var nfts: [NFTAsset] = []
    @State private var isLoadingNFTs = false
    @State private var fees: TransactionFees?
    @State private var simulationStatus: TransactionPreviewView.SimulationStatus = .pending
    @State private var errorMessage: String?

    private let rpcClient: SolanaRPCClient
    private let transactionBuilder: TransactionBuilder
    @StateObject private var confirmationTracker: ConfirmationTracker

    init() {
        let rpc = SolanaRPCClient(rpcURL: AppConfig.defaultRPCURL)
        self.rpcClient = rpc
        self.transactionBuilder = TransactionBuilder(rpcClient: rpc)
        _confirmationTracker = StateObject(wrappedValue: ConfirmationTracker(rpcClient: rpc))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Button {
                    if step == .recipient {
                        dismiss()
                    } else {
                        goBack()
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Group {
                switch step {
                case .recipient:
                    recipientStep
                case .nftSelect:
                    nftSelectStep
                case .preview:
                    previewStep
                case .confirming:
                    confirmingStep
                }
            }
            .padding()

            if let error = errorMessage {
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
        switch step {
        case .recipient: return "Send NFT -- Recipient"
        case .nftSelect: return "Send NFT -- Select NFT"
        case .preview: return "Send NFT -- Preview"
        case .confirming: return "Send NFT -- Confirming"
        }
    }

    // MARK: - Navigation

    private func goBack() {
        switch step {
        case .recipient: break
        case .nftSelect: step = .recipient
        case .preview: step = .nftSelect
        case .confirming: break
        }
    }

    // MARK: - Step 1: Recipient

    private var recipientStep: some View {
        VStack(spacing: 20) {
            RecipientPickerView(
                recipientAddress: $recipientAddress,
                isValid: $recipientValid
            )

            Spacer()

            Button("Next") {
                step = .nftSelect
                loadNFTs()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!recipientValid)
        }
    }

    // MARK: - Step 2: NFT Select

    private var nftSelectStep: some View {
        NFTSelectorView(
            nfts: nfts,
            onSelect: { nft in
                selectedNFT = nft
                step = .preview
                simulateNFTSend()
            },
            isLoading: isLoadingNFTs
        )
    }

    // MARK: - Step 3: Preview

    private var previewStep: some View {
        VStack(spacing: 20) {
            if let nft = selectedNFT, let fees = fees {
                UnifiedTransactionPreviewView(preview: TransactionPreview(
                    actionDescription: "Send NFT: \(nft.name)",
                    balanceChanges: [],
                    feeBreakdown: fees,
                    simulationStatus: mapSimulationStatus(simulationStatus),
                    warnings: []
                ))
            } else {
                ProgressView("Building transaction...")
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel") {
                    goBack()
                }
                .buttonStyle(.bordered)

                Button("Approve & Send") {
                    Task { await approveNFTSend() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(fees == nil)
            }
        }
    }

    // MARK: - Step 4: Confirming

    private var confirmingStep: some View {
        VStack(spacing: 20) {
            ConfirmationView(tracker: confirmationTracker)

            Spacer()

            if case .finalized = confirmationTracker.status {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            } else if case .failed = confirmationTracker.status {
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Logic

    private func loadNFTs() {
        guard let wallet = walletService.activeWallet else { return }
        isLoadingNFTs = true
        Task {
            do {
                let heliusClient = HeliusClient(apiKey: AppConfig.defaultHeliusAPIKey)
                let nftService = NFTService(heliusClient: heliusClient)
                nfts = try await nftService.fetchNFTs(owner: wallet.address)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoadingNFTs = false
        }
    }

    private func simulateNFTSend() {
        simulationStatus = .pending
        Task {
            do {
                guard let wallet = walletService.activeWallet,
                      let nft = selectedNFT else { return }
                let signer = try loadSigner(for: wallet)
                let recipient = try SolanaPublicKey(base58: recipientAddress)

                let (transaction, txFees) = try await transactionBuilder.buildSendNFT(
                    from: signer,
                    to: recipient,
                    mint: nft.mint
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
            } catch {
                simulationStatus = .failed(error: error.localizedDescription)
            }
        }
    }

    private func approveNFTSend() async {
        guard let wallet = walletService.activeWallet,
              let nft = selectedNFT else {
            errorMessage = "No wallet or NFT selected"
            return
        }

        step = .confirming
        errorMessage = nil

        do {
            let signer = try loadSigner(for: wallet)
            let recipient = try SolanaPublicKey(base58: recipientAddress)

            let (transaction, txFees) = try await transactionBuilder.buildSendNFT(
                from: signer,
                to: recipient,
                mint: nft.mint
            )
            self.fees = txFees

            let signature = try await transactionBuilder.submitViaJito(transaction: transaction)
            await confirmationTracker.track(signature: signature)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSigner(for wallet: Wallet) throws -> SoftwareSigner {
        switch wallet.source {
        case .keypairFile(let path):
            let keypair = try KeypairReader.read(from: path)
            return try SoftwareSigner(keypair: keypair)
        case .keychain:
            let seed = try KeychainManager.retrieveSeed(address: wallet.address)
            return try SoftwareSigner(seed: seed)
        case .hardware:
            throw SolanaError.decodingError("Hardware wallet signing not yet supported")
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
