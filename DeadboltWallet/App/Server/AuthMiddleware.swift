import Foundation
import Hummingbird
import DeadboltCore

/// Tracks failed auth attempts for rate limiting.
actor AuthRateLimiter {
    private var failedAttempts: [Date] = []
    private let maxAttempts = 5
    private let windowSeconds: TimeInterval = 60

    func recordFailure() {
        failedAttempts.append(Date())
        pruneOld()
    }

    func isBlocked() -> Bool {
        pruneOld()
        return failedAttempts.count >= maxAttempts
    }

    func reset() {
        failedAttempts.removeAll()
    }

    private func pruneOld() {
        let cutoff = Date().addingTimeInterval(-windowSeconds)
        failedAttempts.removeAll { $0 < cutoff }
    }
}

/// Middleware that validates Bearer token auth on all API requests.
/// Includes rate limiting: 5 failed attempts within 60 seconds triggers a lockout.
struct AuthMiddleware<Context: RequestContext>: RouterMiddleware {
    let config: AppConfig
    let rateLimiter: AuthRateLimiter

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        // Check rate limit before processing
        if await rateLimiter.isBlocked() {
            return rateLimitedResponse()
        }

        // Extract Bearer token
        guard let authHeader = request.headers[.authorization] else {
            await rateLimiter.recordFailure()
            return unauthorizedResponse("Missing Authorization header")
        }

        let prefix = "Bearer "
        guard authHeader.hasPrefix(prefix) else {
            await rateLimiter.recordFailure()
            return unauthorizedResponse("Invalid Authorization format. Expected: Bearer <token>")
        }

        let token = String(authHeader.dropFirst(prefix.count))

        guard await config.validateToken(token) else {
            await rateLimiter.recordFailure()
            return unauthorizedResponse("Invalid API token")
        }

        // Successful auth — reset failure counter
        await rateLimiter.reset()
        return try await next(request, context)
    }

    private struct APIErrorBody: Encodable {
        let error: String
        let code: Int
    }

    private func unauthorizedResponse(_ message: String) -> Response {
        let payload = APIErrorBody(error: message, code: 401)
        let body = (try? JSONEncoder().encode(payload))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? #"{"error":"unauthorized","code":401}"#
        return Response(
            status: .unauthorized,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(string: body))
        )
    }

    private func rateLimitedResponse() -> Response {
        let payload = APIErrorBody(error: "Too many failed authentication attempts. Try again later.", code: 429)
        let body = (try? JSONEncoder().encode(payload))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? #"{"error":"rate limited","code":429}"#
        return Response(
            status: .tooManyRequests,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(string: body))
        )
    }
}
