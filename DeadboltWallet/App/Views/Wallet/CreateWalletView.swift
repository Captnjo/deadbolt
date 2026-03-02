import SwiftUI
import DeadboltCore

/// P8-008: Create wallet view.
/// Options: Generate Random, Generate with Vanity Prefix, Import from Seed Phrase, Import from File.
struct CreateWalletView: View {
    @EnvironmentObject var walletService: WalletService
    @Environment(\.dismiss) private var dismiss

    enum Mode: Hashable {
        case menu
        case generateRandom
        case vanity
        case importSeedPhrase
    }

    @State private var mode: Mode = .menu
    @State private var generatedKeypair: Keypair?
    @State private var generatedWords: [String]?
    @State private var vanityPrefix: String = ""
    @State private var vanityProgress: Int = 0
    @State private var isGenerating = false
    @State private var seedPhraseInput: String = ""
    @State private var errorMessage: String?
    @State private var clipboardCountdown: Int = 0
    @State private var clipboardClearTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Button {
                    if mode == .menu {
                        dismiss()
                    } else {
                        mode = .menu
                        generatedKeypair = nil
                        generatedWords = nil
                        errorMessage = nil
                    }
                } label: {
                    Image(systemName: mode == .menu ? "xmark" : "chevron.left")
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Create Wallet")
                    .font(.headline)

                Spacer()

                Color.clear.frame(width: 24)
            }
            .padding()

            Divider()

            Group {
                switch mode {
                case .menu:
                    menuView
                case .generateRandom:
                    generateRandomView
                case .vanity:
                    vanityView
                case .importSeedPhrase:
                    importSeedPhraseView
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
        .frame(minWidth: 500, minHeight: 400)
    }

    // MARK: - Menu

    private var menuView: some View {
        VStack(spacing: 12) {
            Text("Choose how to create a new wallet")
                .foregroundStyle(.secondary)

            Spacer()

            menuButton(title: "Generate Random", icon: "dice.fill", description: "Create a new random wallet") {
                mode = .generateRandom
                generateRandomWallet()
            }

            menuButton(title: "Vanity Address", icon: "textformat", description: "Generate an address with a custom prefix") {
                mode = .vanity
            }

            menuButton(title: "Import Seed Phrase", icon: "text.word.spacing", description: "Restore from 12 or 24 word mnemonic") {
                mode = .importSeedPhrase
            }

            Spacer()
        }
    }

    private func menuButton(title: String, icon: String, description: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Generate Random

    private var generateRandomView: some View {
        VStack(spacing: 16) {
            if let keypair = generatedKeypair {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)

                Text("Wallet Created")
                    .font(.title2)
                    .fontWeight(.bold)

                // Show seed phrase warning
                if let words = generatedWords {
                    seedPhraseWarning(words: words)
                }

                // Address
                VStack(alignment: .leading, spacing: 4) {
                    Text("Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(keypair.publicKey.base58)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding()
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer()

                Button("Done") {
                    walletService.loadWallets()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            } else if isGenerating {
                Spacer()
                ProgressView("Generating wallet...")
                Spacer()
            }
        }
    }

    private func generateRandomWallet() {
        isGenerating = true
        errorMessage = nil

        Task {
            do {
                // Generate mnemonic and derive keypair
                let words = try Mnemonic.generate(wordCount: 12)
                let keypair = try Mnemonic.importFromPhrase(words: words)

                self.generatedWords = words
                self.generatedKeypair = keypair
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    // MARK: - Vanity

    private var vanityView: some View {
        VStack(spacing: 16) {
            if let keypair = generatedKeypair {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)

                Text("Vanity Wallet Created")
                    .font(.title2)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(keypair.publicKey.base58)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding()
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer()

                Button("Done") {
                    walletService.loadWallets()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Enter a prefix for your wallet address (1-4 characters recommended).")
                    .foregroundStyle(.secondary)

                TextField("Prefix (e.g. 'abc')", text: $vanityPrefix)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                if isGenerating {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Grinding... \(vanityProgress) attempts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Generate") {
                    generateVanityWallet()
                }
                .buttonStyle(.borderedProminent)
                .disabled(vanityPrefix.isEmpty || isGenerating)
            }
        }
    }

    private func generateVanityWallet() {
        isGenerating = true
        errorMessage = nil
        vanityProgress = 0

        Task {
            do {
                let keypair = try await WalletGenerator.grindVanityAddress(
                    prefix: vanityPrefix,
                    maxAttempts: 5_000_000,
                    progressCallback: { attempts in
                        Task { @MainActor in
                            vanityProgress = attempts
                        }
                    }
                )
                self.generatedKeypair = keypair
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    // MARK: - Import Seed Phrase

    private var importSeedPhraseView: some View {
        VStack(spacing: 16) {
            if let keypair = generatedKeypair {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)

                Text("Wallet Imported")
                    .font(.title2)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(keypair.publicKey.base58)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding()
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer()

                Button("Done") {
                    walletService.loadWallets()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Enter your 12 or 24 word seed phrase, separated by spaces.")
                    .foregroundStyle(.secondary)

                TextEditor(text: $seedPhraseInput)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100)
                    .border(Color.secondary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer()

                Button("Import") {
                    importSeedPhrase()
                }
                .buttonStyle(.borderedProminent)
                .disabled(seedPhraseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func importSeedPhrase() {
        errorMessage = nil

        let words = seedPhraseInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }

        guard words.count == 12 || words.count == 24 else {
            errorMessage = "Seed phrase must be 12 or 24 words. Got \(words.count) words."
            return
        }

        do {
            let keypair = try Mnemonic.importFromPhrase(words: words)
            self.generatedKeypair = keypair
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Seed Phrase Warning

    private func seedPhraseWarning(words: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Write down your seed phrase!")
                    .fontWeight(.bold)
                    .foregroundStyle(.red)
            }

            Text("This is the ONLY way to recover your wallet. Store it securely offline. Never share it with anyone.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Display words in a grid
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
                // Auto-clear clipboard after 30 seconds
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
    }
}
