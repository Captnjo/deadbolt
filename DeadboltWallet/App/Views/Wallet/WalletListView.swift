import SwiftUI
import UniformTypeIdentifiers
import DeadboltCore

/// P8-006: Wallet management list view.
/// Lists all wallets with name, short address, balance.
/// Active wallet is highlighted. Add wallet button opens CreateWalletView.
struct WalletListView: View {
    @EnvironmentObject var walletService: WalletService
    @Environment(\.dismiss) private var dismiss

    @State private var showCreateWallet = false
    @State private var showImportKeypair = false

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

                Text("Wallets")
                    .font(.headline)

                Spacer()

                Menu {
                    Button("Create New Wallet") {
                        showCreateWallet = true
                    }
                    Button("Import Keypair File") {
                        showImportKeypair = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            .padding()

            Divider()

            if walletService.wallets.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "wallet.pass")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No wallets found")
                        .foregroundStyle(.secondary)
                    Button("Create Wallet") {
                        showCreateWallet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(walletService.wallets) { wallet in
                            walletRow(wallet)

                            if wallet.id != walletService.wallets.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 450, minHeight: 400)
        .sheet(isPresented: $showCreateWallet) {
            CreateWalletView()
                .environmentObject(walletService)
        }
        .sheet(isPresented: $showImportKeypair) {
            ImportKeypairView()
                .environmentObject(walletService)
        }
    }

    private func walletRow(_ wallet: Wallet) -> some View {
        let isActive = walletService.activeWallet?.id == wallet.id

        return Button {
            // P8-007: Wallet switching
            walletService.activeWallet = wallet
            Task {
                let config = AppConfig()
                await config.update(activeWallet: wallet.address)
                try? await config.save()
                await walletService.refreshDashboard()
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(wallet.name)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        if isActive {
                            Text("Active")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    Text(wallet.address)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(sourceLabel(wallet.source))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isActive ? Color.accentColor.opacity(0.1) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sourceLabel(_ source: WalletSource) -> String {
        switch source {
        case .keypairFile: return "Keypair file"
        case .keychain: return "Keychain"
        case .hardware: return "Hardware wallet"
        }
    }
}

/// P8-005: Import wallet from keypair file view.
struct ImportKeypairView: View {
    @EnvironmentObject var walletService: WalletService
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showFileImporter = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Import Keypair File")
                .font(.title2)
                .fontWeight(.bold)

            Text("Select a Solana keypair JSON file (64-byte array).")
                .foregroundStyle(.secondary)

            Button("Choose File...") {
                #if os(macOS)
                importKeypairFilePanel()
                #else
                showFileImporter = true
                #endif
            }
            .buttonStyle(.borderedProminent)

            if let success = successMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(success)
                }
                .font(.caption)
            }

            if let error = errorMessage {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                }
                .font(.caption)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 250)
        #if !os(macOS)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleFileImportResult(result)
        }
        #endif
    }

    /// Import a keypair file from the selected URL.
    private func importKeypairFromURL(_ url: URL) {
        do {
            let keypair = try KeypairReader.read(from: url.path)
            try walletService.importToKeychain(keypair: keypair)
            walletService.loadWallets()
            successMessage = "Imported wallet: \(keypair.publicKey.shortAddress)"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            successMessage = nil
        }
    }

    #if os(macOS)
    private func importKeypairFilePanel() {
        let panel = NSOpenPanel()
        panel.title = "Select Keypair File"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            importKeypairFromURL(url)
        }
    }
    #else
    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Could not access file"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            importKeypairFromURL(url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
    #endif
}
