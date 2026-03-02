import SwiftUI
import UniformTypeIdentifiers
import DeadboltCore

/// P8-006: Wallet management list view.
/// Lists all wallets with name, short address, balance.
/// Active wallet is highlighted. Add wallet button opens CreateWalletView.
struct WalletListView: View {
    @EnvironmentObject var walletService: WalletService
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var showCreateWallet = false
    @State private var showImportKeypair = false
    @State private var walletToDelete: Wallet?
    @State private var revealedMnemonic: [String]?
    @State private var revealedWalletAddress: String?
    @State private var clipboardCountdown: Int = 0
    @State private var clipboardClearTask: Task<Void, Never>?
    @State private var managingWallet: Wallet?

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
                                .contextMenu {
                                    if wallet.source == .keychain {
                                        Button {
                                            revealSeedPhrase(for: wallet)
                                        } label: {
                                            Label("Show Seed Phrase", systemImage: "eye")
                                        }
                                    }

                                    Button(role: .destructive) {
                                        walletToDelete = wallet
                                    } label: {
                                        Label("Remove Wallet", systemImage: "trash")
                                    }
                                }

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
        .alert("Remove Wallet?", isPresented: Binding(
            get: { walletToDelete != nil },
            set: { if !$0 { walletToDelete = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let wallet = walletToDelete {
                    walletService.removeWallet(wallet)
                    walletToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                walletToDelete = nil
            }
        } message: {
            if let wallet = walletToDelete {
                switch wallet.source {
                case .keychain:
                    Text("This will delete the private key from Keychain. Make sure you have a backup.")
                case .keypairFile:
                    Text("This will hide the wallet from the list. The keypair file on disk will not be deleted.")
                case .hardware:
                    Text("This will de-register the hardware wallet from the app.")
                }
            }
        }
        .sheet(item: $managingWallet) { wallet in
            ManageWalletView(wallet: wallet)
                .environmentObject(walletService)
                .environmentObject(authService)
        }
        .sheet(isPresented: Binding(
            get: { revealedMnemonic != nil },
            set: { if !$0 {
                revealedMnemonic = nil
                revealedWalletAddress = nil
                clipboardClearTask?.cancel()
                clipboardCountdown = 0
            }}
        )) {
            if let words = revealedMnemonic {
                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        Button {
                            revealedMnemonic = nil
                            revealedWalletAddress = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                    }

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title)
                        .foregroundStyle(.yellow)

                    Text("Seed Phrase")
                        .font(.title2)
                        .fontWeight(.bold)

                    if let addr = revealedWalletAddress {
                        Text(addr)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Text("Never share this with anyone. Anyone with these words can steal your funds.")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: 4) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            HStack(spacing: 4) {
                                Text("\(index + 1).")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, alignment: .trailing)
                                Text(word)
                                    .font(.system(.caption, design: .monospaced))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button(clipboardCountdown > 0 ? "Copied — clearing in \(clipboardCountdown)s" : "Copy Seed Phrase") {
                        let phrase = words.joined(separator: " ")
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(phrase, forType: .string)
                        #else
                        UIPasteboard.general.setObjects([phrase as NSString], localOnly: true, expirationDate: Date().addingTimeInterval(30))
                        #endif
                        clipboardCountdown = 30
                        clipboardClearTask?.cancel()
                        clipboardClearTask = Task {
                            for i in stride(from: 29, through: 0, by: -1) {
                                try? await Task.sleep(nanoseconds: 1_000_000_000)
                                clipboardCountdown = i
                            }
                            #if os(macOS)
                            if NSPasteboard.general.string(forType: .string) == phrase {
                                NSPasteboard.general.clearContents()
                            }
                            #endif
                            clipboardCountdown = 0
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(clipboardCountdown > 0)

                    Spacer()
                }
                .padding(24)
                .frame(minWidth: 400, minHeight: 350)
            }
        }
    }

    private func walletRow(_ wallet: Wallet) -> some View {
        let isActive = walletService.activeWallet?.id == wallet.id

        return HStack {
            Button {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                managingWallet = wallet
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
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

    private func revealSeedPhrase(for wallet: Wallet) {
        Task {
            let success = await authService.authenticate(reason: "Authenticate to reveal seed phrase")
            if success {
                showMnemonic(for: wallet)
            }
        }
    }

    private func showMnemonic(for wallet: Wallet) {
        guard let words = KeychainManager.retrieveMnemonic(address: wallet.address) else {
            return
        }
        revealedMnemonic = words
        revealedWalletAddress = wallet.address
    }
}

/// Manage Wallet modal: rename, show seed phrase, remove wallet.
private struct ManageWalletView: View {
    let wallet: Wallet
    @EnvironmentObject var walletService: WalletService
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var editedName: String = ""
    @State private var showRemoveConfirm = false
    @State private var revealedMnemonic: [String]?
    @State private var clipboardCountdown: Int = 0
    @State private var clipboardClearTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }

            Text("Manage Wallet")
                .font(.title2)
                .fontWeight(.bold)

            Text(wallet.shortAddress)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Divider()

            // Rename section
            VStack(alignment: .leading, spacing: 8) {
                Text("Wallet Name")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    TextField("Wallet name", text: $editedName)
                        .textFieldStyle(.roundedBorder)

                    Button("Save") {
                        walletService.renameWallet(wallet, to: editedName)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Divider()

            // Seed phrase (keychain only)
            if wallet.source == .keychain {
                if let words = revealedMnemonic {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("Seed Phrase")
                                .fontWeight(.medium)
                        }

                        Text("Never share this with anyone.")
                            .font(.caption)
                            .foregroundStyle(.red)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                        ], spacing: 4) {
                            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                                HStack(spacing: 4) {
                                    Text("\(index + 1).")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20, alignment: .trailing)
                                    Text(word)
                                        .font(.system(.caption, design: .monospaced))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(8)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button(clipboardCountdown > 0 ? "Copied — clearing in \(clipboardCountdown)s" : "Copy Seed Phrase") {
                            let phrase = words.joined(separator: " ")
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(phrase, forType: .string)
                            #else
                            UIPasteboard.general.setObjects([phrase as NSString], localOnly: true, expirationDate: Date().addingTimeInterval(30))
                            #endif
                            clipboardCountdown = 30
                            clipboardClearTask?.cancel()
                            clipboardClearTask = Task {
                                for i in stride(from: 29, through: 0, by: -1) {
                                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                                    clipboardCountdown = i
                                }
                                #if os(macOS)
                                if NSPasteboard.general.string(forType: .string) == phrase {
                                    NSPasteboard.general.clearContents()
                                }
                                #endif
                                clipboardCountdown = 0
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(clipboardCountdown > 0)
                    }
                } else {
                    Button {
                        Task {
                            let success = await authService.authenticate(reason: "Authenticate to reveal seed phrase")
                            if success {
                                if let words = KeychainManager.retrieveMnemonic(address: wallet.address) {
                                    revealedMnemonic = words
                                }
                            }
                        }
                    } label: {
                        Label("Show Seed Phrase", systemImage: "eye")
                    }
                    .buttonStyle(.bordered)
                }

                Divider()
            }

            // Remove wallet
            Button(role: .destructive) {
                showRemoveConfirm = true
            } label: {
                Label("Remove Wallet", systemImage: "trash")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 400, minHeight: 350)
        .onAppear {
            editedName = wallet.name
        }
        .alert("Remove Wallet?", isPresented: $showRemoveConfirm) {
            Button("Remove", role: .destructive) {
                walletService.removeWallet(wallet)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            switch wallet.source {
            case .keychain:
                Text("This will delete the private key from Keychain. Make sure you have a backup.")
            case .keypairFile:
                Text("This will hide the wallet from the list. The keypair file on disk will not be deleted.")
            case .hardware:
                Text("This will de-register the hardware wallet from the app.")
            }
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
