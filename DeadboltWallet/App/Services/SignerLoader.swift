import Foundation
import DeadboltCore
#if os(macOS)
import HardwareWallet
#endif

/// Shared signer loader that handles keypair file, keychain seed,
/// and ESP32 hardware wallet detection/connection.
@MainActor
final class SignerLoader: ObservableObject {
    @Published var hardwareWalletPrompt: String?

    #if os(macOS)
    private var esp32Bridge: ESP32SerialBridge?
    #endif

    private let walletService: WalletService

    init(walletService: WalletService) {
        self.walletService = walletService
    }

    var isHardwareWallet: Bool {
        walletService.activeWallet?.source == .hardware
    }

    /// Load the appropriate signer for the active wallet.
    func loadSigner() async throws -> TransactionSigner {
        guard let wallet = walletService.activeWallet else {
            throw SolanaError.decodingError("No wallet selected")
        }
        return try await loadSigner(for: wallet)
    }

    /// Load the appropriate signer for the given wallet source.
    func loadSigner(for wallet: Wallet) async throws -> TransactionSigner {
        switch wallet.source {
        case .keypairFile(let path):
            let keypair = try KeypairReader.read(from: path)
            return try SoftwareSigner(keypair: keypair)
        case .keychain:
            let seed = try KeychainManager.retrieveSeed(address: wallet.address)
            return try SoftwareSigner(seed: seed)
        case .hardware:
            #if os(macOS)
            return try await loadHardwareSigner(wallet: wallet)
            #else
            throw SolanaError.decodingError("Hardware wallet is not supported on iOS")
            #endif
        }
    }

    #if os(macOS)
    private func loadHardwareSigner(wallet: Wallet) async throws -> TransactionSigner {
        let detector = ESP32Detector()
        let ports = await detector.scan()

        guard let portPath = ports.first else {
            throw SolanaError.decodingError("No ESP32 hardware wallet detected. Please connect your device.")
        }

        guard let port = ORSSerialPortAdapter(path: portPath, baudRate: ESP32SerialBridge.defaultBaudRate) else {
            throw SolanaError.decodingError("Failed to open serial port at \(portPath)")
        }

        let bridge = ESP32SerialBridge(port: port, onAwaitingConfirmation: { [weak self] in
            Task { @MainActor [weak self] in
                self?.hardwareWalletPrompt = "Press BOOT button on ESP32 to approve transaction"
            }
        })
        try await bridge.connect()

        // Verify device identity matches registered wallet
        let devicePubkey = await bridge.publicKey
        if devicePubkey.base58 != wallet.address {
            await bridge.disconnect()
            throw SolanaError.decodingError("Hardware wallet public key mismatch. Expected \(wallet.address.prefix(8))..., got \(devicePubkey.base58.prefix(8))...")
        }

        self.esp32Bridge = bridge
        return bridge
    }
    #endif

    func clearPrompt() {
        hardwareWalletPrompt = nil
    }
}
