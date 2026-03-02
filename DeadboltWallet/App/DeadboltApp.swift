import SwiftUI
import DeadboltCore
#if os(macOS)
import HardwareWallet
#endif

/// P8-015: Main app entry point with sidebar navigation.
/// Phase 2: Embedded Intent API server for AI agent signing gateway.
@main
struct DeadboltApp: App {
    @StateObject private var walletService = WalletService()
    @StateObject private var agentService = AgentService()
    #if os(macOS)
    @State private var showBootDetect = true
    @State private var unsecuredKeypairs: [UnsecuredKeypair] = []
    @State private var showKeypairMigration = false
    #endif

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
            TabView {
                DashboardView()
                    .environmentObject(walletService)
                    .tabItem { Label("Dashboard", systemImage: "house") }

                if let wallet = walletService.activeWallet {
                    TransactionHistoryView(walletAddress: wallet.address)
                        .environmentObject(walletService)
                        .tabItem { Label("History", systemImage: "clock") }
                }

                WalletListView()
                    .environmentObject(walletService)
                    .tabItem { Label("Wallets", systemImage: "wallet.pass") }

                AddressBookView()
                    .tabItem { Label("Address Book", systemImage: "person.crop.rectangle.stack") }
            }
            .task {
                let migrationService = MigrationService()
                await migrationService.migrateIfNeeded()
            }
            #else
            ZStack {
                NavigationSplitView {
                    sidebarContent
                } detail: {
                    DashboardView()
                        .environmentObject(walletService)
                }
                .navigationSplitViewStyle(.balanced)
                .opacity(showBootDetect ? 0.3 : 1.0)
                .disabled(showBootDetect)

                if showBootDetect {
                    HardwareWalletBootView(isPresented: $showBootDetect)
                        .environmentObject(walletService)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 20)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Agent signing prompt overlay
                if let request = agentService.currentRequest {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    AgentSigningPromptView(request: request)
                        .environmentObject(agentService)
                        .environmentObject(walletService)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showBootDetect)
            .animation(.easeInOut(duration: 0.3), value: agentService.currentRequest?.id)
            .task {
                let migrationService = MigrationService()
                await migrationService.migrateIfNeeded()
                // Scan for unsecured keypair files
                let found = await migrationService.scanForUnsecuredKeypairs()
                if !found.isEmpty {
                    unsecuredKeypairs = found
                    showKeypairMigration = true
                }
            }
            .task {
                agentService.walletService = walletService
                await agentService.startServer()
            }
            .alert("Unsecured Keypairs Found", isPresented: $showKeypairMigration) {
                Button("Import to Keychain & Delete Files") {
                    Task {
                        let service = MigrationService()
                        for kp in unsecuredKeypairs {
                            do {
                                try await service.importAndSecureDelete(path: kp.path, deleteOriginal: true)
                            } catch {
                                print("Failed to import keypair \(kp.address.prefix(8))...: \(error.localizedDescription)")
                            }
                        }
                        await walletService.loadWallets()
                        unsecuredKeypairs = []
                    }
                }
                Button("Import to Keychain Only") {
                    Task {
                        let service = MigrationService()
                        for kp in unsecuredKeypairs {
                            do {
                                try await service.importAndSecureDelete(path: kp.path, deleteOriginal: false)
                            } catch {
                                print("Failed to import keypair \(kp.address.prefix(8))...: \(error.localizedDescription)")
                            }
                        }
                        await walletService.loadWallets()
                        unsecuredKeypairs = []
                    }
                }
                Button("Skip", role: .cancel) {
                    unsecuredKeypairs = []
                }
            } message: {
                Text("\(unsecuredKeypairs.count) unencrypted keypair file\(unsecuredKeypairs.count == 1 ? "" : "s") found on disk. These are readable by any local process. Import to Keychain for secure storage.")
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 800, height: 600)
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var sidebarContent: some View {
        List {
            NavigationLink {
                DashboardView()
                    .environmentObject(walletService)
            } label: {
                Label("Dashboard", systemImage: "house")
            }

            NavigationLink {
                if let wallet = walletService.activeWallet {
                    TransactionHistoryView(walletAddress: wallet.address)
                        .environmentObject(walletService)
                } else {
                    Text("No wallet selected")
                        .foregroundStyle(.secondary)
                }
            } label: {
                Label("History", systemImage: "clock")
            }

            NavigationLink {
                WalletListView()
                    .environmentObject(walletService)
            } label: {
                Label("Wallets", systemImage: "wallet.pass")
            }

            NavigationLink {
                AddressBookView()
            } label: {
                Label("Address Book", systemImage: "person.crop.rectangle.stack")
            }

            NavigationLink {
                NativeStakeView()
                    .environmentObject(walletService)
            } label: {
                Label("Native Staking", systemImage: "lock.shield")
            }

            NavigationLink {
                HardwareWalletSettingsView()
                    .environmentObject(walletService)
            } label: {
                Label("Hardware Wallet", systemImage: "cpu")
            }

            NavigationLink {
                AgentAPIView()
                    .environmentObject(agentService)
            } label: {
                Label("Agent API", systemImage: "antenna.radiowaves.left.and.right")
            }

            Divider()

            NavigationLink {
                SettingsView()
                    .environmentObject(walletService)
            } label: {
                Label("Settings", systemImage: "gear")
            }
        }
        .navigationTitle("Deadbolt")
        .listStyle(.sidebar)
    }
    #endif
}
