import SwiftUI
import DeadboltCore

struct SettingsView: View {
    @EnvironmentObject var walletService: WalletService
    @State private var selectedNetwork: SolanaNetwork = .mainnet

    var body: some View {
        Form {
            Section("Network") {
                Picker("Solana Network", selection: $selectedNetwork) {
                    ForEach(SolanaNetwork.allCases, id: \.self) { network in
                        Text(network.displayName).tag(network)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedNetwork) { _, newValue in
                    guard newValue != walletService.network else { return }
                    Task {
                        await walletService.switchNetwork(newValue)
                    }
                }

                HStack {
                    Text("RPC")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(selectedNetwork.rpcURL(heliusAPIKey: AppConfig.defaultHeliusAPIKey).host ?? "")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section("Preferences") {
                Toggle("Jito MEV Protection", isOn: .constant(true))
                    .disabled(true)
            }

            Section("Agent API") {
                NavigationLink("Guardrails") {
                    GuardrailsSettingsView()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            selectedNetwork = walletService.network
        }
    }
}
