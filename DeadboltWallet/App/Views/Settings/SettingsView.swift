import SwiftUI
import DeadboltCore

struct SettingsView: View {
    @EnvironmentObject var walletService: WalletService
    @State private var selectedNetwork: SolanaNetwork = .mainnet
    @State private var heliusAPIKey: String = ""
    @State private var heliusKeySaved = false
    @State private var jupiterAPIKey: String = ""
    @State private var jupiterKeySaved = false
    @State private var dflowAPIKey: String = ""
    @State private var dflowKeySaved = false
    @State private var preferredAggregator: String = "dflow"

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

                HStack {
                    SecureField("Helius API Key", text: $heliusAPIKey)
                        .textFieldStyle(.roundedBorder)

                    Button(heliusKeySaved ? "Saved" : "Save") {
                        Task {
                            await walletService.updateHeliusAPIKey(heliusAPIKey)
                            heliusKeySaved = true
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            heliusKeySaved = false
                        }
                    }
                    .disabled(heliusAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || heliusKeySaved)
                }
            }

            Section("Swap") {
                Picker("Default Aggregator", selection: $preferredAggregator) {
                    Text("DFlow").tag("dflow")
                    Text("Jupiter").tag("jupiter")
                }
                .pickerStyle(.segmented)
                .onChange(of: preferredAggregator) { _, newValue in
                    Task {
                        await walletService.updatePreferredSwapAggregator(newValue)
                    }
                }

                HStack {
                    SecureField("DFlow API Key", text: $dflowAPIKey)
                        .textFieldStyle(.roundedBorder)

                    Button(dflowKeySaved ? "Saved" : "Save") {
                        Task {
                            await walletService.updateDFlowAPIKey(dflowAPIKey)
                            dflowKeySaved = true
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            dflowKeySaved = false
                        }
                    }
                    .disabled(dflowAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dflowKeySaved)
                }

                Link("Get a key at pond.dflow.net/build/api-key",
                     destination: URL(string: "https://pond.dflow.net/build/api-key")!)
                    .font(.caption)

                HStack {
                    SecureField("Jupiter API Key", text: $jupiterAPIKey)
                        .textFieldStyle(.roundedBorder)

                    Button(jupiterKeySaved ? "Saved" : "Save") {
                        Task {
                            await walletService.updateJupiterAPIKey(jupiterAPIKey)
                            jupiterKeySaved = true
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            jupiterKeySaved = false
                        }
                    }
                    .disabled(jupiterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || jupiterKeySaved)
                }

                Link("Get a free key at portal.jup.ag",
                     destination: URL(string: "https://portal.jup.ag")!)
                    .font(.caption)
            }

            Section("Preferences") {
                Toggle("Jito MEV Protection", isOn: .constant(true))
                    .disabled(true)
            }

            Section("Security") {
                NavigationLink("Authentication") {
                    AuthSettingsView()
                }
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
            let currentKey = AppConfig.defaultHeliusAPIKey
            if currentKey != "MISSING_HELIUS_API_KEY" {
                heliusAPIKey = currentKey
            }
            let currentJupKey = AppConfig.defaultJupiterAPIKey
            if !currentJupKey.isEmpty {
                jupiterAPIKey = currentJupKey
            }
            let currentDFlowKey = AppConfig.defaultDFlowAPIKey
            if !currentDFlowKey.isEmpty {
                dflowAPIKey = currentDFlowKey
            }
            preferredAggregator = AppConfig.defaultPreferredSwapAggregator
        }
    }
}
