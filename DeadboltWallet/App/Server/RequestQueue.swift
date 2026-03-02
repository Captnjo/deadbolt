import Foundation

// MARK: - Agent Request

struct AgentRequest: Sendable, Identifiable {
    let id: String
    let intent: IntentRequest
    var status: IntentStatus
    var preview: IntentPreview?
    var signature: String?
    var slot: UInt64?
    var error: String?
    let createdAt: Date
    var updatedAt: Date

    init(id: String, intent: IntentRequest) {
        self.id = id
        self.intent = intent
        self.status = .pendingApproval
        self.preview = nil
        self.signature = nil
        self.slot = nil
        self.error = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func toResponse() -> IntentResponse {
        IntentResponse(
            requestId: id,
            status: status,
            preview: preview,
            signature: signature,
            slot: slot,
            error: error
        )
    }
}

// MARK: - Request Queue Actor

actor RequestQueue {
    private var requests: [String: AgentRequest] = [:]
    private var pendingOrder: [String] = [] // FIFO order for pending requests

    /// Stream for notifying UI about new pending requests.
    private var continuations: [UUID: AsyncStream<AgentRequest>.Continuation] = [:]

    // MARK: - Enqueue

    func enqueue(_ intent: IntentRequest) -> AgentRequest {
        let requestId = "req_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(16))"
        let request = AgentRequest(id: requestId, intent: intent)
        requests[requestId] = request
        pendingOrder.append(requestId)

        // Notify listeners
        for (_, continuation) in continuations {
            continuation.yield(request)
        }

        return request
    }

    // MARK: - Query

    func get(_ id: String) -> AgentRequest? {
        requests[id]
    }

    func listPending() -> [AgentRequest] {
        pendingOrder.compactMap { id in
            guard let req = requests[id], req.status == .pendingApproval else { return nil }
            return req
        }
    }

    func nextPending() -> AgentRequest? {
        for id in pendingOrder {
            if let req = requests[id], req.status == .pendingApproval {
                return req
            }
        }
        return nil
    }

    var pendingCount: Int {
        pendingOrder.filter { id in
            requests[id]?.status == .pendingApproval
        }.count
    }

    /// Returns all requests updated after the given date.
    func getUpdatedSince(_ date: Date) -> [AgentRequest] {
        requests.values
            .filter { $0.updatedAt > date }
            .sorted { $0.updatedAt < $1.updatedAt }
    }

    // MARK: - Status Updates

    func updateStatus(_ id: String, status: IntentStatus) {
        guard requests[id] != nil else { return }
        requests[id]?.status = status
        requests[id]?.updatedAt = Date()

        // Remove from pending order when no longer pending
        if status != .pendingApproval {
            pendingOrder.removeAll { $0 == id }
        }
    }

    func setPreview(_ id: String, preview: IntentPreview) {
        requests[id]?.preview = preview
        requests[id]?.updatedAt = Date()
    }

    func setConfirmed(_ id: String, signature: String, slot: UInt64?) {
        requests[id]?.status = .confirmed
        requests[id]?.signature = signature
        requests[id]?.slot = slot
        requests[id]?.updatedAt = Date()
        pendingOrder.removeAll { $0 == id }
    }

    func setFailed(_ id: String, error: String) {
        requests[id]?.status = .failed
        requests[id]?.error = error
        requests[id]?.updatedAt = Date()
        pendingOrder.removeAll { $0 == id }
    }

    func setRejected(_ id: String) {
        requests[id]?.status = .rejected
        requests[id]?.updatedAt = Date()
        pendingOrder.removeAll { $0 == id }
    }

    // MARK: - Subscription Stream

    func subscribe() -> AsyncStream<AgentRequest> {
        let subId = UUID()
        return AsyncStream { continuation in
            continuations[subId] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(subId) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    // MARK: - Scheduled / DCA Templates

    private var scheduledTemplates: [String: ScheduledIntent] = [:]

    struct ScheduledIntent: Sendable {
        let intent: IntentRequest
        let intervalSeconds: TimeInterval
        let remainingCount: Int
        let lastSubmittedAt: Date?
    }

    func addSchedule(intent: IntentRequest, intervalSeconds: TimeInterval, count: Int) -> String {
        let id = "sched_\(UUID().uuidString.prefix(8))"
        scheduledTemplates[id] = ScheduledIntent(
            intent: intent,
            intervalSeconds: intervalSeconds,
            remainingCount: count,
            lastSubmittedAt: nil
        )
        return id
    }

    func checkSchedules() -> [IntentRequest] {
        var toSubmit: [IntentRequest] = []
        let now = Date()

        for (id, schedule) in scheduledTemplates {
            guard schedule.remainingCount > 0 else {
                scheduledTemplates.removeValue(forKey: id)
                continue
            }

            let shouldSubmit: Bool
            if let lastSubmitted = schedule.lastSubmittedAt {
                shouldSubmit = now.timeIntervalSince(lastSubmitted) >= schedule.intervalSeconds
            } else {
                shouldSubmit = true
            }

            if shouldSubmit {
                toSubmit.append(schedule.intent)
                scheduledTemplates[id] = ScheduledIntent(
                    intent: schedule.intent,
                    intervalSeconds: schedule.intervalSeconds,
                    remainingCount: schedule.remainingCount - 1,
                    lastSubmittedAt: now
                )
            }
        }

        return toSubmit
    }

    // MARK: - Cleanup

    func removeOlderThan(_ date: Date) {
        let staleIds = requests.filter { $0.value.createdAt < date && $0.value.status != .pendingApproval }.map(\.key)
        for id in staleIds {
            requests.removeValue(forKey: id)
        }
    }
}
