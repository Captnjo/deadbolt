#if os(macOS)
import SwiftUI
import DeadboltCore
import HardwareWallet

/// P6-010: Hardware wallet settings view.
/// Shows connection status, detected device, public key.
/// Provides buttons to detect device, generate new key, and disconnect.
struct HardwareWalletSettingsView: View {
    @EnvironmentObject var walletService: WalletService
    @Environment(\.dismiss) private var dismiss

    @State private var connectionStatus: ConnectionStatus = .disconnected
    @State private var detectedPortPath: String?
    @State private var devicePublicKey: String?
    @State private var errorMessage: String?
    @State private var isProcessing = false

    private enum ConnectionStatus {
        case disconnected, detecting, connected

        var label: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .detecting: return "Detecting..."
            case .connected: return "Connected"
            }
        }

        var color: Color {
            switch self {
            case .disconnected: return .red
            case .detecting: return .orange
            case .connected: return .green
            }
        }
    }

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

                Text("Hardware Wallet")
                    .font(.headline)

                Spacer()

                // Spacer for symmetry
                Color.clear.frame(width: 20, height: 20)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // Connection Status Card
                    statusCard

                    // Device Info Card
                    deviceInfoCard

                    // Actions
                    actionButtons
                }
                .padding()
            }

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
        .task {
            await detectDevice()
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Connection Status")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionStatus.color)
                        .frame(width: 10, height: 10)
                    Text(connectionStatus.label)
                        .font(.subheadline)
                        .foregroundStyle(connectionStatus.color)
                }
            }

            if let portPath = detectedPortPath {
                HStack {
                    Text("Port")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(portPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Device Info Card

    private var deviceInfoCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Device Info")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }

            if let pubkey = devicePublicKey {
                HStack {
                    Text("Public Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(pubkey)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(pubkey, forType: .string)
                } label: {
                    Label("Copy Public Key", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            } else {
                Text("No device detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                Task { await detectDevice() }
            } label: {
                Label("Detect Device", systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessing)

            Button {
                Task { await generateNewKey() }
            } label: {
                Label("Generate New Key", systemImage: "key.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isProcessing || connectionStatus != .connected)

            Button(role: .destructive) {
                Task { await disconnectDevice() }
            } label: {
                Label("Disconnect", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(connectionStatus == .disconnected)
        }
    }

    // MARK: - Actions

    private func detectDevice() async {
        isProcessing = true
        errorMessage = nil
        connectionStatus = .detecting

        let detector = ESP32Detector()
        let ports = await detector.scan()

        if let portPath = ports.first {
            self.detectedPortPath = portPath

            // Try to connect and get public key
            do {
                guard let port = ORSSerialPortAdapter(path: portPath, baudRate: ESP32SerialBridge.defaultBaudRate) else {
                    throw HardwareWalletError.connectionFailed("Failed to open serial port at \(portPath)")
                }
                let bridge = ESP32SerialBridge(port: port)
                try await bridge.connect()
                let pubkey = await bridge.publicKey
                self.devicePublicKey = pubkey.base58
                connectionStatus = .connected
                await bridge.disconnect()

                // Register hardware wallet on the dashboard
                let alreadyExists = walletService.wallets.contains { $0.address == pubkey.base58 }
                if !alreadyExists {
                    let hwWallet = Wallet(publicKey: pubkey, name: "Hardware Wallet", source: .hardware)
                    walletService.wallets.append(hwWallet)
                }
                if walletService.activeWallet == nil {
                    walletService.activeWallet = walletService.wallets.first { $0.address == pubkey.base58 }
                    Task { await walletService.refreshDashboard() }
                }
            } catch {
                errorMessage = "Device found but connection failed: \(error.localizedDescription)"
                connectionStatus = .disconnected
            }
        } else {
            detectedPortPath = nil
            devicePublicKey = nil
            connectionStatus = .disconnected
            errorMessage = "No ESP32 device detected. Check USB connection."
        }

        isProcessing = false
    }

    private func generateNewKey() async {
        guard let portPath = detectedPortPath else {
            errorMessage = "No device connected"
            return
        }

        isProcessing = true
        errorMessage = nil

        do {
            guard let port = ORSSerialPortAdapter(path: portPath, baudRate: ESP32SerialBridge.defaultBaudRate) else {
                errorMessage = "Failed to open serial port at \(portPath)"
                isProcessing = false
                return
            }
            let bridge = ESP32SerialBridge(port: port)
            try await bridge.connect()
            let newKey = try await bridge.generateKeypair()
            self.devicePublicKey = newKey.base58
            await bridge.disconnect()

            // Register the hardware wallet with the wallet service
            walletService.wallets.append(
                Wallet(publicKey: newKey, name: "Hardware Wallet", source: .hardware)
            )
        } catch {
            errorMessage = "Failed to generate key: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    private func disconnectDevice() async {
        detectedPortPath = nil
        devicePublicKey = nil
        connectionStatus = .disconnected
        errorMessage = nil
    }
}
#endif
