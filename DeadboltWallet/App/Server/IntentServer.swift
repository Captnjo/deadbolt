import Foundation
import Hummingbird
import DeadboltCore

/// Embedded HTTP server for the Intent API. Listens on localhost:9876.
actor IntentServer {
    private var app: (any ApplicationProtocol)?
    private var serverTask: Task<Void, any Error>?
    private let requestQueue: RequestQueue
    private let config: AppConfig
    private let walletStateProvider: WalletStateProvider
    private let guardrailsEngine: GuardrailsEngine
    let port: Int

    private(set) var isRunning = false
    private var activeSubscribers = 0
    private static let maxSubscribers = 5

    init(requestQueue: RequestQueue, config: AppConfig, walletStateProvider: WalletStateProvider, guardrailsEngine: GuardrailsEngine, port: Int = 9876) {
        self.requestQueue = requestQueue
        self.config = config
        self.walletStateProvider = walletStateProvider
        self.guardrailsEngine = guardrailsEngine
        self.port = port
    }

    // MARK: - Lifecycle

    func start() async throws {
        guard !isRunning else { return }

        let router = buildRouter()
        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname("127.0.0.1", port: port)
            )
        )

        self.app = app
        isRunning = true

        serverTask = Task {
            try await app.run()
        }
    }

    func stop() {
        serverTask?.cancel()
        serverTask = nil
        isRunning = false
    }

    // MARK: - Router

    private func buildRouter() -> Router<BasicRequestContext> {
        let router = Router()

        // Health check — no auth required
        router.get("api/v1/health") { _, _ -> Response in
            let body = """
            {"status":"ok","service":"deadbolt","version":"2.0"}
            """
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: body))
            )
        }

        // Apply auth middleware to API group
        let api = router.group("api/v1")
        let authRateLimiter = AuthRateLimiter()
        api.add(middleware: AuthMiddleware<BasicRequestContext>(config: config, rateLimiter: authRateLimiter))

        // POST /api/v1/intent — submit an intent
        let queue = requestQueue
        let engine = guardrailsEngine
        api.post("intent") { request, context -> Response in
            do {
                let body = try await request.body.collect(upTo: 1_048_576) // 1MB limit
                let decoder = JSONDecoder()
                let intent = try decoder.decode(IntentRequest.self, from: body)

                // Evaluate guardrails before queuing
                let solPrice = (try? await PriceService().fetchSOLPrice()) ?? 150.0

                // For batch intents, evaluate each sub-intent individually
                if case .batch(let batchParams) = intent.params {
                    for (i, subIntent) in batchParams.intents.enumerated() {
                        let subResult = await engine.evaluate(subIntent, solPrice: solPrice)
                        if case .rejected(let reason) = subResult {
                            return Self.errorResponse("Guardrail rejected sub-intent \(i + 1): \(reason)", code: 403, status: .forbidden)
                        }
                    }
                }

                let result = await engine.evaluate(intent, solPrice: solPrice)
                if case .rejected(let reason) = result {
                    return Self.errorResponse("Guardrail rejected: \(reason)", code: 403, status: .forbidden)
                }

                let agentRequest = await queue.enqueue(intent)

                // Build initial preview
                let preview = IntentPreview(
                    action: Self.describeIntent(intent),
                    fees: nil,
                    warnings: [],
                    simulation: nil,
                    balanceChanges: nil
                )
                await queue.setPreview(agentRequest.id, preview: preview)

                let response = IntentResponse(
                    requestId: agentRequest.id,
                    status: .pendingApproval,
                    preview: preview,
                    signature: nil,
                    slot: nil,
                    error: nil
                )

                return try Self.jsonResponse(response, status: .ok)
            } catch let error as DecodingError {
                return Self.errorResponse("Invalid request body: \(error.localizedDescription)", code: 400, status: .badRequest)
            } catch {
                return Self.errorResponse("Internal error: \(error.localizedDescription)", code: 500, status: .internalServerError)
            }
        }

        // GET /api/v1/status/:request_id — check intent status
        api.get("status/:request_id") { request, context -> Response in
            guard let requestId = context.parameters.get("request_id") else {
                return Self.errorResponse("Missing request_id", code: 400, status: .badRequest)
            }

            guard let agentRequest = await queue.get(requestId) else {
                return Self.errorResponse("Request not found: \(requestId)", code: 404, status: .notFound)
            }

            let response = agentRequest.toResponse()
            return (try? Self.jsonResponse(response, status: .ok))
                ?? Self.errorResponse("Serialization error", code: 500, status: .internalServerError)
        }

        // MARK: - Query Endpoints

        let stateProvider = walletStateProvider

        // GET /api/v1/wallet — active wallet info
        api.get("wallet") { _, _ -> Response in
            let state = await stateProvider.getWalletState()
            let json: [String: Any] = [
                "address": state.address ?? "",
                "source": state.source,
                "network": state.network
            ]
            return Self.dictResponse(json)
        }

        // GET /api/v1/balance — SOL balance + portfolio value
        api.get("balance") { _, _ -> Response in
            let state = await stateProvider.getBalanceState()
            let json: [String: Any] = [
                "sol_lamports": state.solLamports,
                "sol_display": state.solDisplay,
                "sol_usd": state.solUSD,
                "total_portfolio_usd": state.totalPortfolioUSD
            ]
            return Self.dictResponse(json)
        }

        // GET /api/v1/tokens — token holdings
        api.get("tokens") { _, _ -> Response in
            let tokens = await stateProvider.getTokenBalances()
            let tokenDicts = tokens.map { t in
                [
                    "mint": t.mint,
                    "symbol": t.symbol,
                    "amount": t.amount,
                    "usd_value": t.usdValue
                ] as [String: Any]
            }
            return Self.arrayResponse(tokenDicts)
        }

        // GET /api/v1/price?mint= — price for a token
        api.get("price") { request, _ -> Response in
            let mint = request.uri.queryParameters.get("mint") ?? ""
            guard !mint.isEmpty else {
                return Self.errorResponse("Missing 'mint' query parameter", code: 400, status: .badRequest)
            }
            let price = await stateProvider.getPrice(mint: mint)
            let json: [String: Any] = ["mint": mint, "price_usd": price]
            return Self.dictResponse(json)
        }

        // GET /api/v1/subscribe — long-poll for status updates (bridge uses this)
        // Subscriber counter is managed via a thread-safe counter actor
        let subscriberCounter = SubscriberCounter()
        api.get("subscribe") { request, _ -> Response in
            // Enforce max concurrent subscribers
            let allowed = await subscriberCounter.tryAcquire(max: 5)
            guard allowed else {
                return Self.errorResponse("Too many concurrent subscribers", code: 429, status: .tooManyRequests)
            }
            defer { Task { await subscriberCounter.release() } }

            let sinceStr = request.uri.queryParameters.get("since") ?? ""
            let timeoutStr = request.uri.queryParameters.get("timeout") ?? "30"
            let timeoutSec = min(Double(timeoutStr) ?? 30.0, 60.0)

            let sinceDate: Date
            if let sinceInterval = Double(sinceStr) {
                sinceDate = Date(timeIntervalSince1970: sinceInterval)
            } else {
                sinceDate = Date.distantPast
            }

            // Check for already-available updates
            let existing = await queue.getUpdatedSince(sinceDate)
            if !existing.isEmpty {
                let updates = existing.map { req in
                    [
                        "request_id": req.id,
                        "status": req.status.rawValue,
                        "signature": req.signature ?? "",
                        "error": req.error ?? "",
                        "updated_at": String(req.updatedAt.timeIntervalSince1970)
                    ] as [String: Any]
                }
                let payload: [String: Any] = [
                    "updates": updates,
                    "server_time": String(Date().timeIntervalSince1970)
                ]
                return Self.dictResponse(payload)
            }

            // Long-poll: wait for up to timeoutSec for a new update
            let deadline = Date().addingTimeInterval(timeoutSec)
            while Date() < deadline {
                try await Task.sleep(for: .milliseconds(500))
                let updates = await queue.getUpdatedSince(sinceDate)
                if !updates.isEmpty {
                    let updateDicts = updates.map { req in
                        [
                            "request_id": req.id,
                            "status": req.status.rawValue,
                            "signature": req.signature ?? "",
                            "error": req.error ?? "",
                            "updated_at": String(req.updatedAt.timeIntervalSince1970)
                        ] as [String: Any]
                    }
                    let payload: [String: Any] = [
                        "updates": updateDicts,
                        "server_time": String(Date().timeIntervalSince1970)
                    ]
                    return Self.dictResponse(payload)
                }
            }

            // Timeout — no updates
            let payload: [String: Any] = [
                "updates": [] as [[String: Any]],
                "server_time": String(Date().timeIntervalSince1970)
            ]
            return Self.dictResponse(payload)
        }

        // GET /api/v1/history — recent transactions
        api.get("history") { request, _ -> Response in
            let limitStr = request.uri.queryParameters.get("limit") ?? "20"
            let limit = min(max(Int(limitStr) ?? 20, 1), 100) // Clamp to [1, 100]
            let entries = await stateProvider.getHistory(limit: limit)
            let historyDicts = entries.map { e in
                [
                    "signature": e.signature,
                    "type": e.type,
                    "description": e.description,
                    "timestamp": e.timestamp
                ] as [String: Any]
            }
            return Self.arrayResponse(historyDicts)
        }

        return router
    }

    // MARK: - Intent Description

    static func describeIntent(_ intent: IntentRequest) -> String {
        switch intent.params {
        case .sendSol(let p):
            let sol = Double(p.amount) / 1_000_000_000.0
            let shortRecipient = String(p.recipient.prefix(8)) + "..."
            return "Send \(formatSOL(sol)) SOL to \(shortRecipient)"

        case .sendToken(let p):
            let shortRecipient = String(p.recipient.prefix(8)) + "..."
            let shortMint = String(p.mint.prefix(8)) + "..."
            return "Send \(p.amount) of \(shortMint) to \(shortRecipient)"

        case .swap(let p):
            let inputAmount = Double(p.amount) / 1_000_000_000.0 // approximate, depends on token decimals
            let shortInput = String(p.inputMint.prefix(8)) + "..."
            let shortOutput = String(p.outputMint.prefix(8)) + "..."
            return "Swap \(formatSOL(inputAmount)) \(shortInput) → \(shortOutput)"

        case .stake(let p):
            let sol = Double(p.amount) / 1_000_000_000.0
            let shortLst = String(p.lstMint.prefix(8)) + "..."
            return "Stake \(formatSOL(sol)) SOL → \(shortLst)"

        case .signMessage(let p):
            let preview = p.message.prefix(50)
            return "Sign message: \"\(preview)\(p.message.count > 50 ? "..." : "")\""

        case .createWallet(let p):
            let source = p.source ?? "hot"
            let name = p.name ?? "New Wallet"
            return "Create \(source) wallet: \(name)"

        case .batch(let p):
            return "Batch: \(p.intents.count) operations"
        }
    }

    private static func formatSOL(_ amount: Double) -> String {
        if amount == Double(Int(amount)) {
            return String(Int(amount))
        }
        return String(format: "%.4f", amount)
    }

    // MARK: - Response Helpers

    static func jsonResponse<T: Encodable>(_ value: T, status: HTTPResponse.Status) throws -> Response {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data))
        )
    }

    static func dictResponse(_ dict: [String: Any]) -> Response {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) else {
            return errorResponse("Serialization error", code: 500, status: .internalServerError)
        }
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data))
        )
    }

    static func arrayResponse(_ array: [[String: Any]]) -> Response {
        guard let data = try? JSONSerialization.data(withJSONObject: array, options: [.sortedKeys]) else {
            return errorResponse("Serialization error", code: 500, status: .internalServerError)
        }
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data))
        )
    }

    private struct APIErrorBody: Encodable {
        let error: String
        let code: Int
    }

    static func errorResponse(_ message: String, code: Int, status: HTTPResponse.Status) -> Response {
        let payload = APIErrorBody(error: message, code: code)
        let body = (try? JSONEncoder().encode(payload))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? #"{"error":"internal error","code":500}"#
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(string: body))
        )
    }
}

/// Thread-safe counter for limiting concurrent subscribe connections.
actor SubscriberCounter {
    private var count = 0

    func tryAcquire(max: Int) -> Bool {
        guard count < max else { return false }
        count += 1
        return true
    }

    func release() {
        count = max(0, count - 1)
    }
}
