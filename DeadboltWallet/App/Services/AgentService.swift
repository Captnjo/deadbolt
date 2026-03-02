import Foundation
import SwiftUI
import DeadboltCore

/// Manages the embedded Intent API server and agent request queue.
@MainActor
final class AgentService: ObservableObject {
    @Published var isServerRunning = false
    @Published var serverPort: Int = 9876
    @Published var pendingRequestCount = 0
    @Published var currentRequest: AgentRequest?
    @Published var serverError: String?
    @Published var apiToken: String?

    let requestQueue = RequestQueue()
    private(set) var guardrailsEngine: GuardrailsEngine?
    private var intentServer: IntentServer?
    private(set) var config: AppConfig?
    private var subscriptionTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    var walletService: WalletService?

    // MARK: - Server Lifecycle

    func startServer() async {
        let config = AppConfig()
        self.config = config
        do {
            try await config.load()
        } catch {
            // First launch — no config file yet
        }

        // Ensure we have an API token
        if await config.apiToken == nil {
            let token = await config.generateAPIToken()
            try? await config.save()
            apiToken = token
        } else {
            apiToken = await config.apiToken
        }

        let engine = GuardrailsEngine(config: config)
        self.guardrailsEngine = engine

        let stateProvider: WalletStateProvider
        if let ws = walletService {
            stateProvider = WalletServiceStateProvider(walletService: ws)
        } else {
            stateProvider = WalletServiceStateProvider(walletService: WalletService())
        }
        let server = IntentServer(requestQueue: requestQueue, config: config, walletStateProvider: stateProvider, guardrailsEngine: engine, port: serverPort)
        self.intentServer = server

        do {
            try await server.start()
            isServerRunning = true
            serverError = nil
            startListening()
            startCleanupTimer()
        } catch {
            isServerRunning = false
            serverError = "Failed to start server: \(error.localizedDescription)"
        }
    }

    func stopServer() async {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        cleanupTask?.cancel()
        cleanupTask = nil
        await intentServer?.stop()
        isServerRunning = false
    }

    func regenerateToken() async {
        guard let config = config else { return }
        let token = await config.generateAPIToken()
        try? await config.save()
        apiToken = token
    }

    func revokeToken() async {
        guard let config = config else { return }
        await config.update(apiToken: nil)
        try? await config.save()
        apiToken = nil
    }

    // MARK: - Request Management

    func approveRequest(_ id: String) async {
        await requestQueue.updateStatus(id, status: .signing)
        currentRequest = nil
        // Actual signing is handled by the signing prompt view
        await updatePendingCount()
    }

    func rejectRequest(_ id: String) async {
        await requestQueue.setRejected(id)
        currentRequest = nil
        await updatePendingCount()
    }

    // MARK: - Subscription

    /// Periodically clean up completed/failed requests older than 1 hour.
    private func startCleanupTimer() {
        cleanupTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600)) // Every hour
                if Task.isCancelled { break }
                let cutoff = Date().addingTimeInterval(-3600) // 1 hour ago
                await requestQueue.removeOlderThan(cutoff)
            }
        }
    }

    private func startListening() {
        subscriptionTask = Task {
            let stream = await requestQueue.subscribe()
            for await request in stream {
                if !Task.isCancelled {
                    self.currentRequest = request
                    await self.updatePendingCount()
                }
            }
        }
    }

    private func updatePendingCount() async {
        pendingRequestCount = await requestQueue.pendingCount
    }
}
