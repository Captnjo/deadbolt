#if os(macOS)
import SwiftUI
import DeadboltCore
import HardwareWallet

/// Boot-time modal that auto-detects the ESP32 hardware wallet.
/// Shows scanning status, connection progress, and auto-dismisses on success.
struct HardwareWalletBootView: View {
    @EnvironmentObject var walletService: WalletService
    @Binding var isPresented: Bool

    enum DetectState: Equatable {
        case scanning
        case found(port: String)
        case connecting
        case connected(address: String)
        case failed(message: String)
    }

    @State private var state: DetectState = .scanning
    @State private var dotCount = 0

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: iconName)
                .font(.system(size: 48))
                .foregroundStyle(iconColor)
                .symbolEffect(.pulse, isActive: isPulsing)

            // Title
            Text(title)
                .font(.title2)
                .fontWeight(.bold)

            // Subtitle
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Progress or action
            switch state {
            case .scanning, .found, .connecting:
                ProgressView()
                    .controlSize(.large)

            case .connected(let address):
                VStack(spacing: 8) {
                    Text(address)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

            case .failed:
                HStack(spacing: 12) {
                    Button("Retry") {
                        Task { await detect() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Skip") {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(40)
        .frame(width: 400, height: 300)
        .task {
            await detect()
        }
    }

    private var iconName: String {
        switch state {
        case .scanning: return "antenna.radiowaves.left.and.right"
        case .found: return "cable.connector"
        case .connecting: return "cpu"
        case .connected: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch state {
        case .scanning, .found, .connecting: return .accentColor
        case .connected: return .green
        case .failed: return .orange
        }
    }

    private var isPulsing: Bool {
        switch state {
        case .scanning, .connecting: return true
        default: return false
        }
    }

    private var title: String {
        switch state {
        case .scanning: return "Scanning for Hardware Wallet"
        case .found(let port): return "Found Device"
        case .connecting: return "Connecting..."
        case .connected: return "Hardware Wallet Connected"
        case .failed: return "Connection Failed"
        }
    }

    private var subtitle: String {
        switch state {
        case .scanning: return "Looking for ESP32 on USB..."
        case .found(let port): return port
        case .connecting: return "Establishing serial connection..."
        case .connected: return "Your wallet is ready."
        case .failed(let msg): return msg
        }
    }

    private func detect() async {
        state = .scanning
        NSLog("[BootView] detect() called")

        let detector = ESP32Detector()
        let ports = await detector.scan()
        NSLog("[BootView] scan returned %d ports", ports.count)

        guard let portPath = ports.first else {
            state = .failed(message: "No ESP32 device found.\nPlug in your hardware wallet and try again.")
            return
        }

        state = .found(port: portPath)
        try? await Task.sleep(nanoseconds: 300_000_000)

        state = .connecting

        do {
            guard let port = ORSSerialPortAdapter(path: portPath, baudRate: ESP32SerialBridge.defaultBaudRate) else {
                state = .failed(message: "Could not open serial port at \(portPath)")
                return
            }
            let bridge = ESP32SerialBridge(port: port)
            try await bridge.connect()
            let pubkey = await bridge.publicKey
            NSLog("[BootView] connected, pubkey=%@", pubkey.base58)
            await bridge.disconnect()

            // Verify device identity if a hardware wallet is already registered
            let existingHW = walletService.wallets.first { $0.source == .hardware }
            if let existing = existingHW, existing.address != pubkey.base58 {
                state = .failed(message: "Device public key mismatch.\nExpected: \(existing.address.prefix(8))...\nGot: \(pubkey.base58.prefix(8))...\n\nThis may be a different or compromised device.")
                return
            }

            // Register with wallet service
            let alreadyExists = walletService.wallets.contains { $0.address == pubkey.base58 }
            if !alreadyExists {
                let hwWallet = Wallet(publicKey: pubkey, name: "Hardware Wallet", source: .hardware)
                walletService.wallets.append(hwWallet)
            }
            walletService.activeWallet = walletService.wallets.first { $0.address == pubkey.base58 }

            state = .connected(address: pubkey.base58)

            // Brief pause to show success, then dismiss and load dashboard
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            isPresented = false
            await walletService.refreshDashboard()
        } catch {
            NSLog("[BootView] FAILED: %@", error.localizedDescription)
            state = .failed(message: error.localizedDescription)
        }
    }
}
#endif
