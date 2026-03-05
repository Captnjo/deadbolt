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
    @StateObject private var authService = AuthService()
    @State private var dashboardSheet: DashboardView.ActiveSheet?
    #if os(macOS)
    @State private var showBootDetect = true
    @State private var unsecuredKeypairs: [UnsecuredKeypair] = []
    @State private var showKeypairMigration = false
    #endif

    init() {
        #if os(macOS)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            let size = icon.size
            let radius = size.width * 0.2 // macOS-style corner radius
            let rounded = NSImage(size: size, flipped: false) { rect in
                let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
                path.addClip()
                icon.draw(in: rect)
                return true
            }
            NSApplication.shared.applicationIconImage = rounded
        }

        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
            TabView {
                DashboardView(activeSheet: $dashboardSheet)
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
            .environmentObject(authService)
            .preferredColorScheme(.dark)
            .tint(Brand.solarFlare)
            .sheet(isPresented: $authService.showPasswordEntry) {
                PasswordEntryView()
                    .environmentObject(authService)
            }
            .task {
                await authService.loadFromConfig()
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
                    DashboardView(activeSheet: $dashboardSheet)
                        .environmentObject(walletService)
                }
                .navigationSplitViewStyle(.balanced)

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
                        .environmentObject(authService)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .environmentObject(authService)
            .preferredColorScheme(.dark)
            .tint(Brand.solarFlare)
            .sheet(isPresented: $authService.showPasswordEntry) {
                PasswordEntryView()
                    .environmentObject(authService)
            }
            .sheet(item: $dashboardSheet) { sheet in
                Group {
                    switch sheet {
                    case .send:
                        UnifiedSendView(walletService: walletService, authService: authService)
                            .environmentObject(walletService)
                            .environmentObject(authService)
                    case .sendNFT:
                        SendNFTFlowView()
                            .environmentObject(walletService)
                    case .receive:
                        ReceiveView()
                            .environmentObject(walletService)
                    case .swap:
                        UnifiedSwapView(walletService: walletService, authService: authService)
                            .environmentObject(walletService)
                            .environmentObject(authService)
                    case .stake:
                        UnifiedStakeView(walletService: walletService, authService: authService)
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
                    }
                }
                .sheetToolbarFix()
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
                await authService.loadFromConfig()
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
                DashboardView(activeSheet: $dashboardSheet)
                    .environmentObject(walletService)
                    .environmentObject(authService)
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
                    .environmentObject(authService)
            } label: {
                Label("Wallets", systemImage: "wallet.pass")
            }

            NavigationLink {
                AddressBookView()
            } label: {
                Label("Address Book", systemImage: "person.crop.rectangle.stack")
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
                    .environmentObject(authService)
            } label: {
                Label("Agent API", systemImage: "antenna.radiowaves.left.and.right")
            }

            Divider()

            NavigationLink {
                SettingsView()
                    .environmentObject(walletService)
                    .environmentObject(authService)
            } label: {
                Label("Settings", systemImage: "gear")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            sidebarHeader
        }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 2) {
            if let logoURL = Bundle.module.url(forResource: "DeadboltLogomark", withExtension: "png"),
               let nsImage = NSImage(contentsOf: logoURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 32)
            }
            Text("EADBOLT")
                .font(.system(size: 15, weight: .bold, design: .default))
                .tracking(1.5)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    #endif
}
