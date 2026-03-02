import Foundation
import DeadboltCore

// MARK: - JSON protocol types

/// A command to send to the ESP32.
struct ESP32Command: Encodable {
    let cmd: String
    var payload: String?
}

/// A response from the ESP32.
struct ESP32Response: Decodable {
    let status: String
    var msg: String?
    var pubkey: String?
    var address: String?
    var signature: String?
}

// MARK: - Thread-safe public key storage

/// Thread-safe, Sendable storage for a `SolanaPublicKey` that can be read
/// from a nonisolated context (required by `TransactionSigner.publicKey`).
final class PublicKeyStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: SolanaPublicKey

    init() {
        // Start with a zero key; callers must call connect()/getPublicKey() before use.
        _value = try! SolanaPublicKey(data: Data(repeating: 0, count: 32))
    }

    var value: SolanaPublicKey {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set(_ key: SolanaPublicKey) {
        lock.lock()
        defer { lock.unlock() }
        _value = key
    }
}

// MARK: - ESP32SerialBridge

/// Communicates with an ESP32 hardware wallet over a serial port using
/// newline-delimited JSON. Conforms to `TransactionSigner` so it can be
/// used interchangeably with `SoftwareSigner`.
///
/// The bridge is an actor to ensure thread-safe access to the serial port
/// and cached state.
public actor ESP32SerialBridge: @preconcurrency TransactionSigner {

    // MARK: - Constants

    /// Default baud rate for ESP32 communication.
    public static let defaultBaudRate = 115_200

    /// Default timeout for simple commands (ping, pubkey, generate).
    public static let defaultTimeout: TimeInterval = 5.0

    /// Timeout for the sign command (user must physically press button).
    public static let signTimeout: TimeInterval = 30.0

    // MARK: - Properties

    private let port: SerialPortProtocol

    /// Thread-safe storage for the public key, accessible from nonisolated context.
    private let _publicKeyStorage = PublicKeyStorage()

    /// The public key of the connected ESP32 hardware wallet.
    /// Fetched from the device on first access and cached.
    /// Callers should call `connect()` or `getPublicKey()` before reading this.
    public nonisolated var publicKey: SolanaPublicKey {
        _publicKeyStorage.value
    }

    // MARK: - Init

    /// Create a bridge using a serial port abstraction.
    /// - Parameter port: A `SerialPortProtocol` implementation (real or mock).
    public init(port: SerialPortProtocol) {
        self.port = port
    }

    // MARK: - Connection

    /// Open the serial port and verify connectivity with a ping.
    public func connect() async throws {
        if !port.isOpen {
            try await port.open()
        }
        // Give the ESP32 a moment to initialize after port open
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        // Flush any stale data in the receive buffer from previous sessions
        port.flushReceiveBuffer()

        // Send a bare newline to reset the ESP32's command parser in case
        // it has a partial command from a broken previous connection
        try await port.send(Data([UInt8(ascii: "\n")]))
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        port.flushReceiveBuffer()

        try await ping()
        // Pre-fetch and cache the public key
        _ = try await getPublicKey()
    }

    /// Close the serial port.
    public func disconnect() {
        port.close()
        _publicKeyStorage.set(try! SolanaPublicKey(data: Data(repeating: 0, count: 32)))
    }

    // MARK: - Commands

    /// Send a ping command and verify the device responds with "pong".
    @discardableResult
    public func ping() async throws -> String {
        let response = try await sendCommand(ESP32Command(cmd: "ping"), timeout: Self.defaultTimeout)
        guard response.status == "ok", response.msg == "pong" else {
            throw HardwareWalletError.invalidResponse(
                "Expected pong, got status=\(response.status) msg=\(response.msg ?? "nil")"
            )
        }
        return "pong"
    }

    /// Request the device's public key.
    /// The result is cached for subsequent calls and for the `publicKey` property.
    @discardableResult
    public func getPublicKey() async throws -> SolanaPublicKey {
        let response = try await sendCommand(ESP32Command(cmd: "pubkey"), timeout: Self.defaultTimeout)
        guard response.status == "ok" else {
            throw HardwareWalletError.invalidResponse("pubkey command failed: \(response.msg ?? "unknown error")")
        }
        guard let hexPubkey = response.pubkey else {
            throw HardwareWalletError.invalidResponse("pubkey response missing pubkey field")
        }

        let pubkeyData = try hexToData(hexPubkey)
        let key = try SolanaPublicKey(data: pubkeyData)
        _publicKeyStorage.set(key)
        return key
    }

    /// Sign a message using the hardware wallet.
    ///
    /// This initiates a multi-step flow:
    /// 1. Send the sign command with the message as hex-encoded payload.
    /// 2. The device responds with a "pending" status asking the user to press the BOOT button.
    /// 3. Wait for either an approval (signed) or rejection (error) within the sign timeout.
    ///
    /// - Parameter message: The raw message bytes to sign.
    /// - Returns: A 64-byte Ed25519 signature.
    public func sign(message: Data) async throws -> Data {
        let hexPayload = message.map { String(format: "%02x", $0) }.joined()
        let command = ESP32Command(cmd: "sign", payload: hexPayload)

        // Send the sign command
        let pendingResponse = try await sendCommand(command, timeout: Self.defaultTimeout)

        // Expect a pending response first
        if pendingResponse.status == "pending" {
            // Now wait for the user to press the button (up to 30 seconds)
            let finalResponse = try await receiveResponse(timeout: Self.signTimeout)

            if finalResponse.status == "signed" {
                guard let hexSig = finalResponse.signature else {
                    throw HardwareWalletError.invalidResponse("signed response missing signature field")
                }
                let sigData = try hexToData(hexSig)
                guard sigData.count == 64 else {
                    throw HardwareWalletError.invalidResponse("Signature must be 64 bytes, got \(sigData.count)")
                }
                return sigData
            } else if finalResponse.status == "error" {
                if finalResponse.msg == "rejected" {
                    throw HardwareWalletError.rejected
                }
                throw HardwareWalletError.invalidResponse(finalResponse.msg ?? "unknown sign error")
            } else {
                throw HardwareWalletError.invalidResponse("Unexpected sign status: \(finalResponse.status)")
            }
        } else if pendingResponse.status == "signed" {
            // Immediate "signed" without "pending" is a protocol violation — user must physically confirm
            #if DEBUG
            // In debug builds, allow immediate signing for test mode
            guard let hexSig = pendingResponse.signature else {
                throw HardwareWalletError.invalidResponse("signed response missing signature field")
            }
            let sigData = try hexToData(hexSig)
            guard sigData.count == 64 else {
                throw HardwareWalletError.invalidResponse("Signature must be 64 bytes, got \(sigData.count)")
            }
            return sigData
            #else
            throw HardwareWalletError.invalidResponse("Device signed without user confirmation (expected 'pending' first). This may indicate a compromised device.")
            #endif
        } else if pendingResponse.status == "error" {
            if pendingResponse.msg == "rejected" {
                throw HardwareWalletError.rejected
            }
            throw HardwareWalletError.invalidResponse(pendingResponse.msg ?? "unknown sign error")
        } else {
            throw HardwareWalletError.invalidResponse("Unexpected sign response status: \(pendingResponse.status)")
        }
    }

    /// Request the device to generate a new keypair.
    /// - Returns: The public key of the newly generated keypair.
    public func generateKeypair() async throws -> SolanaPublicKey {
        let response = try await sendCommand(ESP32Command(cmd: "generate"), timeout: Self.defaultTimeout)
        guard response.status == "ok" else {
            throw HardwareWalletError.invalidResponse("generate command failed: \(response.msg ?? "unknown error")")
        }
        guard let hexPubkey = response.pubkey else {
            throw HardwareWalletError.invalidResponse("generate response missing pubkey field")
        }

        let pubkeyData = try hexToData(hexPubkey)
        let key = try SolanaPublicKey(data: pubkeyData)
        // Update cached key to the newly generated one
        _publicKeyStorage.set(key)
        return key
    }

    // MARK: - Internal protocol helpers

    /// Encode a command as JSON, append newline, send it, and wait for a response.
    private func sendCommand(_ command: ESP32Command, timeout: TimeInterval) async throws -> ESP32Response {
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(command)
        guard var jsonString = String(data: jsonData, encoding: .utf8) else {
            throw HardwareWalletError.invalidResponse("Failed to encode command as UTF-8")
        }
        jsonString.append("\n")

        guard let sendData = jsonString.data(using: .utf8) else {
            throw HardwareWalletError.invalidResponse("Failed to convert command to data")
        }

        try await port.send(sendData)
        return try await receiveResponse(timeout: timeout)
    }

    /// Wait for and parse a JSON response line from the serial port.
    private func receiveResponse(timeout: TimeInterval) async throws -> ESP32Response {
        let data = try await port.receiveLine(timeout: timeout)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ESP32Response.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            throw HardwareWalletError.invalidResponse("Failed to decode response: \(raw)")
        }
    }

    // MARK: - Hex utilities

    /// Convert a hex string to Data.
    private func hexToData(_ hex: String) throws -> Data {
        let chars = Array(hex)
        guard chars.count % 2 == 0 else {
            throw HardwareWalletError.invalidResponse("Hex string has odd length: \(hex.count)")
        }
        var data = Data(capacity: chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            let pair = String(chars[i]) + String(chars[i + 1])
            guard let byte = UInt8(pair, radix: 16) else {
                throw HardwareWalletError.invalidResponse("Invalid hex byte: \(pair)")
            }
            data.append(byte)
        }
        return data
    }
}
