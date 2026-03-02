import Foundation
@testable import HardwareWallet

/// A mock serial port for testing ESP32SerialBridge without physical hardware.
///
/// Configure the mock with responses for each command before running tests.
/// The mock queues responses and delivers them in order when `receiveLine` is called.
final class MockSerialPort: SerialPortProtocol, @unchecked Sendable {

    // MARK: - Configuration

    /// Queued responses to return, in order. Each entry is a JSON string (without trailing newline).
    private var responseQueue: [MockResponse] = []
    private let lock = NSLock()

    /// Track all commands sent to the mock.
    private(set) var sentCommands: [Data] = []

    /// Whether the mock port is currently open.
    var _isOpen = false

    /// If true, `receiveLine` will throw `HardwareWalletError.timeout`.
    var simulateTimeout = false

    /// If set, `open()` will throw this error.
    var openError: Error?

    /// If set, `send()` will throw this error.
    var sendError: Error?

    // MARK: - Response types

    enum MockResponse {
        /// Return this JSON string as a response.
        case json(String)
        /// Throw this error when receiveLine is called.
        case error(Error)
    }

    // MARK: - SerialPortProtocol

    var isOpen: Bool { _isOpen }

    func open() async throws {
        if let error = openError {
            throw error
        }
        _isOpen = true
    }

    func close() {
        _isOpen = false
    }

    func send(_ data: Data) async throws {
        if let error = sendError {
            throw error
        }
        recordSentCommand(data)
    }

    func receiveLine(timeout: TimeInterval) async throws -> Data {
        if simulateTimeout {
            throw HardwareWalletError.timeout
        }
        return try dequeueNextResponse()
    }

    func flushReceiveBuffer() {
        // No-op for mock
    }

    // MARK: - Synchronous lock helpers (avoid NSLock-in-async warnings)

    private func recordSentCommand(_ data: Data) {
        lock.lock()
        sentCommands.append(data)
        lock.unlock()
    }

    private func dequeueNextResponse() throws -> Data {
        lock.lock()
        guard !responseQueue.isEmpty else {
            lock.unlock()
            throw HardwareWalletError.invalidResponse("No more mock responses queued")
        }
        let response = responseQueue.removeFirst()
        lock.unlock()

        switch response {
        case .json(let jsonString):
            guard let data = jsonString.data(using: .utf8) else {
                throw HardwareWalletError.invalidResponse("Failed to encode mock response")
            }
            return data
        case .error(let error):
            throw error
        }
    }

    // MARK: - Test helpers

    /// Queue a JSON response to be returned by the next `receiveLine` call.
    func queueResponse(_ json: String) {
        lock.lock()
        responseQueue.append(.json(json))
        lock.unlock()
    }

    /// Queue an error to be thrown by the next `receiveLine` call.
    func queueError(_ error: Error) {
        lock.lock()
        responseQueue.append(.error(error))
        lock.unlock()
    }

    /// Queue a ping "pong" response.
    func queuePongResponse() {
        queueResponse(#"{"status":"ok","msg":"pong"}"#)
    }

    /// Queue a pubkey response with the given hex public key and base58 address.
    func queuePubkeyResponse(hex: String, address: String) {
        queueResponse(#"{"status":"ok","pubkey":"\#(hex)","address":"\#(address)"}"#)
    }

    /// Queue a sign pending response.
    func queueSignPendingResponse() {
        queueResponse(#"{"status":"pending","msg":"Press BOOT button to approve"}"#)
    }

    /// Queue a signed response with the given hex signature.
    func queueSignedResponse(signatureHex: String) {
        queueResponse(#"{"status":"signed","signature":"\#(signatureHex)"}"#)
    }

    /// Queue a rejection error response.
    func queueRejectionResponse() {
        queueResponse(#"{"status":"error","msg":"rejected"}"#)
    }

    /// Queue a generate keypair response.
    func queueGenerateResponse(hex: String, address: String) {
        queueResponse(#"{"status":"ok","pubkey":"\#(hex)","address":"\#(address)"}"#)
    }

    /// Get the last sent command as a decoded string (without the trailing newline).
    func lastSentCommandString() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let last = sentCommands.last else { return nil }
        var str = String(data: last, encoding: .utf8) ?? ""
        if str.hasSuffix("\n") {
            str.removeLast()
        }
        return str
    }

    /// Reset the mock to its initial state.
    func reset() {
        lock.lock()
        responseQueue.removeAll()
        sentCommands.removeAll()
        lock.unlock()
        _isOpen = false
        simulateTimeout = false
        openError = nil
        sendError = nil
    }
}
