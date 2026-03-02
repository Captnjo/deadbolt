import SwiftUI
import DeadboltCore
#if os(macOS)
import HardwareWallet
#endif

struct DashboardView: View {
    @EnvironmentObject var walletService: WalletService
    @EnvironmentObject var authService: AuthService
    @State private var activeSheet: ActiveSheet?
    @State private var hwConnected = false
    @State private var showErrorAlert = false

    enum ActiveSheet: Identifiable {
        case send, sendToken, sendNFT, receive, swap, stake, history, wallets, addressBook, nativeStake
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            if walletService.activeWallet == nil && !walletService.isLoading {
                // P8-016: "No wallet loaded" empty state
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No wallet connected")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Connect your ESP32 hardware wallet to get started.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else if walletService.isLoading && walletService.solBalance == 0 {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        balanceSection
                        quickActionToolbar
                        secondaryActionToolbar
                        stakedLSTSection
                        tokenSection
                        nftSection
                    }
                    .padding()
                }
            }

            if let error = walletService.errorMessage {
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
        .frame(minWidth: 400, minHeight: 400)
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") { walletService.errorMessage = nil }
        } message: {
            Text(walletService.errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: walletService.errorMessage) { _, newValue in
            showErrorAlert = newValue != nil
        }
        .task {
            walletService.loadWallets()
            walletService.loadTokenDefinitions()
            walletService.loadTokenCache()
            await walletService.refreshDashboard()
            #if os(macOS)
            await checkHardwareWalletConnection()
            #endif
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .send:
                SendFlowView(walletService: walletService, authService: authService)
                    .environmentObject(walletService)
                    .environmentObject(authService)
            case .sendToken:
                SendTokenFlowView(walletService: walletService, authService: authService)
                    .environmentObject(walletService)
                    .environmentObject(authService)
            case .sendNFT:
                SendNFTFlowView()
                    .environmentObject(walletService)
            case .receive:
                ReceiveView()
                    .environmentObject(walletService)
            case .swap:
                SwapFlowView(walletService: walletService, authService: authService)
                    .environmentObject(walletService)
                    .environmentObject(authService)
            case .stake:
                StakeFlowView(walletService: walletService, authService: authService)
                    .environmentObject(walletService)
                    .environmentObject(authService)
            case .history:
                if let wallet = walletService.activeWallet {
                    TransactionHistoryView(walletAddress: wallet.address)
                        .environmentObject(walletService)
                }
            case .wallets:
                WalletListView()
                    .environmentObject(walletService)
                    .environmentObject(authService)
            case .addressBook:
                AddressBookView()
            case .nativeStake:
                NativeStakeView()
                    .environmentObject(walletService)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let wallet = walletService.activeWallet {
                    HStack(spacing: 6) {
                        Text(wallet.name)
                            .font(.headline)

                        if walletService.network == .devnet {
                            Text("DEVNET")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.purple)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        if wallet.source == .hardware {
                            Text("HW")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            // Connection status dot
                            Circle()
                                .fill(hwConnected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                                .help(hwConnected ? "Hardware wallet connected" : "Hardware wallet disconnected")
                        }
                    }
                    HStack(spacing: 4) {
                        Text(wallet.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        Button {
                            activeSheet = .receive
                        } label: {
                            Image(systemName: "qrcode")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Show QR Code")
                    }
                } else {
                    Text("No Wallet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                activeSheet = .wallets
            } label: {
                Image(systemName: "wallet.pass")
            }

            Button {
                activeSheet = .history
            } label: {
                Image(systemName: "clock")
            }

            if walletService.isLoading && walletService.solBalance > 0 {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await walletService.refreshDashboard() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(walletService.isLoading)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding()
    }

    // MARK: - Balance

    private var balanceSection: some View {
        VStack(spacing: 8) {
            Text(DashboardViewModel.formatSOL(walletService.solBalance) + " SOL")
                .font(.system(size: 32, weight: .bold, design: .monospaced))

            if walletService.solPrice > 0 {
                Text(DashboardViewModel.formatUSD(walletService.solUSDValue))
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            if walletService.totalPortfolioUSD > walletService.solUSDValue {
                HStack {
                    Text("Total Portfolio")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(DashboardViewModel.formatUSD(walletService.totalPortfolioUSD))
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Quick Actions

    private var quickActionToolbar: some View {
        HStack(spacing: 12) {
            quickActionButton(title: "Send", icon: "arrow.up.circle.fill", color: .blue) {
                activeSheet = .send
            }
            quickActionButton(title: "Receive", icon: "arrow.down.circle.fill", color: .green) {
                activeSheet = .receive
            }
            quickActionButton(title: "Swap", icon: "arrow.triangle.2.circlepath.circle.fill", color: .orange) {
                activeSheet = .swap
            }
            quickActionButton(title: "Stake", icon: "lock.circle.fill", color: .purple) {
                activeSheet = .stake
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func quickActionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Secondary Actions

    private var secondaryActionToolbar: some View {
        HStack(spacing: 12) {
            quickActionButton(title: "Send Token", icon: "arrow.up.right.circle.fill", color: .teal) {
                activeSheet = .sendToken
            }
            quickActionButton(title: "Send NFT", icon: "photo.circle.fill", color: .indigo) {
                activeSheet = .sendNFT
            }
            quickActionButton(title: "Address Book", icon: "person.crop.rectangle.stack.fill", color: .brown) {
                activeSheet = .addressBook
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Staked LST Section (P5-011)

    private var stakedLSTSection: some View {
        Group {
            let lstMints = Set([LSTMint.jitoSOL, LSTMint.mSOL, LSTMint.bSOL, LSTMint.bonkSOL])
            let lstBalances = walletService.tokenBalances.filter { lstMints.contains($0.definition.mint) }

            if !lstBalances.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Staked")
                        .font(.headline)
                        .padding(.bottom, 4)

                    ForEach(lstBalances) { token in
                        TokenRowView(token: token)
                        if token.id != lstBalances.last?.id {
                            Divider()
                        }
                    }
                }
                .padding()
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Token List

    private var tokenSection: some View {
        Group {
            let lstMints = Set([LSTMint.jitoSOL, LSTMint.mSOL, LSTMint.bSOL, LSTMint.bonkSOL])
            let nonLSTTokens = walletService.tokenBalances.filter { !lstMints.contains($0.definition.mint) }

            VStack(alignment: .leading, spacing: 4) {
                Text("Tokens")
                    .font(.headline)
                    .padding(.bottom, 4)

                if nonLSTTokens.isEmpty {
                    // P8-016: "No tokens found" empty state
                    Text("No tokens found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(nonLSTTokens) { token in
                        TokenRowView(token: token)
                        if token.id != nonLSTTokens.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding()
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - NFT Section (P3-014)

    @State private var nfts: [NFTAsset] = []
    @State private var isLoadingNFTs = false

    private var nftSection: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("NFTs")
                        .font(.headline)
                    Spacer()
                    if !nfts.isEmpty {
                        Text("\(nfts.count) total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isLoadingNFTs {
                    ProgressView("Loading NFTs...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if nfts.isEmpty {
                    Text("No NFTs found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    let displayNFTs = Array(nfts.prefix(6))
                    let columns = [
                        GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 8)
                    ]
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(displayNFTs, id: \.mint.base58) { nft in
                            nftThumbnail(nft)
                        }
                    }

                    if nfts.count > 6 {
                        Button("View All (\(nfts.count))") {
                            activeSheet = .sendNFT
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding()
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .task {
                await loadNFTs()
            }
        }
    }

    private func nftThumbnail(_ nft: NFTAsset) -> some View {
        VStack(spacing: 2) {
            if let urlStr = nft.imageURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        nftPlaceholder
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        nftPlaceholder
                    }
                }
                .frame(width: 70, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                nftPlaceholder
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text(nft.name)
                .font(.caption2)
                .lineLimit(1)
        }
    }

    private var nftPlaceholder: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "photo")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func loadNFTs() async {
        guard let wallet = walletService.activeWallet else { return }
        isLoadingNFTs = true
        do {
            let heliusClient = HeliusClient(apiKey: AppConfig.defaultHeliusAPIKey)
            let nftService = NFTService(heliusClient: heliusClient)
            nfts = try await nftService.fetchNFTs(owner: wallet.address)
        } catch {
            // Silently fail NFT loading -- not critical for dashboard
        }
        isLoadingNFTs = false
    }

    // MARK: - Hardware Wallet Status (P6-009)

    #if os(macOS)
    private func checkHardwareWalletConnection() async {
        guard let wallet = walletService.activeWallet,
              wallet.source == .hardware else {
            hwConnected = false
            return
        }
        let detector = ESP32Detector()
        let ports = await detector.scan()
        hwConnected = !ports.isEmpty
    }
    #endif
}
