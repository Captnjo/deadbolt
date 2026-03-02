import Foundation
import ORSSerial

/// Wraps an `ORSSerialPort` to conform to `SerialPortProtocol`.
///
/// Bridges the delegate-based ORSSerialPort API into async/await using
/// `CheckedContinuation`. Data is buffered internally and lines are extracted
/// when `receiveLine(timeout:)` is called.
public final class ORSSerialPortAdapter: NSObject, SerialPortProtocol, ORSSerialPortDelegate, @unchecked Sendable {

    // MARK: - Properties

    private let serialPort: ORSSerialPort
    private let lock = NSLock()

    /// Buffer for incoming data. Lines are extracted on demand.
    private var receiveBuffer = Data()

    /// Continuation waiting for the next line of data.
    private var lineContinuation: CheckedContinuation<Data, Error>?

    /// Continuation waiting for the port to open.
    private var openContinuation: CheckedContinuation<Void, Error>?

    /// Track whether we've been removed from the system.
    private var removedFromSystem = false

    // MARK: - Init

    /// Create an adapter for the given ORSSerialPort.
    /// - Parameters:
    ///   - port: The ORSSerialPort to wrap.
    ///   - baudRate: Baud rate to configure (default 115200).
    public init(port: ORSSerialPort, baudRate: Int = ESP32SerialBridge.defaultBaudRate) {
        self.serialPort = port
        super.init()
        self.serialPort.baudRate = NSNumber(value: baudRate)
        self.serialPort.delegate = self
    }

    /// Create an adapter for a serial port at the given device path.
    /// - Parameters:
    ///   - path: The device path (e.g. "/dev/cu.usbserial-0001").
    ///   - baudRate: Baud rate to configure (default 115200).
    public convenience init?(path: String, baudRate: Int = ESP32SerialBridge.defaultBaudRate) {
        guard let port = ORSSerialPort(path: path) else {
            return nil
        }
        self.init(port: port, baudRate: baudRate)
    }

    // MARK: - SerialPortProtocol

    public var isOpen: Bool {
        serialPort.isOpen
    }

    public func open() async throws {
        guard !serialPort.isOpen else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.lock.lock()
            self.openContinuation = continuation
            self.lock.unlock()

            self.serialPort.open()

            // Timeout if the port doesn't open within 5 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                if let pending = self.openContinuation {
                    self.openContinuation = nil
                    self.lock.unlock()
                    pending.resume(throwing: HardwareWalletError.timeout)
                } else {
                    self.lock.unlock()
                }
            }
        }
    }

    public func close() {
        serialPort.close()
        lock.lock()
        receiveBuffer.removeAll()
        // Cancel any pending continuation
        let pending = lineContinuation
        lineContinuation = nil
        lock.unlock()
        pending?.resume(throwing: HardwareWalletError.connectionFailed("Port closed"))
    }

    public func send(_ data: Data) async throws {
        guard serialPort.isOpen else {
            throw HardwareWalletError.connectionFailed("Port is not open")
        }
        let success = serialPort.send(data)
        if !success {
            throw HardwareWalletError.serialPortError("Failed to send data")
        }
    }

    public func receiveLine(timeout: TimeInterval) async throws -> Data {
        // Check buffer synchronously first (off the async path)
        if let lineData = checkBufferForLine() {
            return lineData
        }

        // Wait for data with timeout
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            self.lock.lock()

            // Double-check buffer (data may have arrived between our first check and now)
            if let lineData = self.extractLine() {
                self.lock.unlock()
                continuation.resume(returning: lineData)
                return
            }

            self.lineContinuation = continuation
            self.lock.unlock()

            // Set up timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                if let pending = self.lineContinuation {
                    self.lineContinuation = nil
                    self.lock.unlock()
                    pending.resume(throwing: HardwareWalletError.timeout)
                } else {
                    self.lock.unlock()
                }
            }
        }
    }

    public func flushReceiveBuffer() {
        lock.lock()
        receiveBuffer.removeAll()
        lock.unlock()
    }

    /// Check the buffer for a complete line, with locking. Nonisolated-safe.
    private func checkBufferForLine() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return extractLine()
    }

    // MARK: - ORSSerialPortDelegate

    public func serialPortWasRemovedFromSystem(_ serialPort: ORSSerialPort) {
        lock.lock()
        removedFromSystem = true
        let pendingLine = lineContinuation
        lineContinuation = nil
        let pendingOpen = openContinuation
        openContinuation = nil
        lock.unlock()
        pendingLine?.resume(throwing: HardwareWalletError.connectionFailed("Device removed from system"))
        pendingOpen?.resume(throwing: HardwareWalletError.connectionFailed("Device removed from system"))
    }

    public func serialPort(_ serialPort: ORSSerialPort, didReceive data: Data) {
        lock.lock()
        receiveBuffer.append(data)

        // Try to extract a complete line and resume any waiting continuation
        if let lineData = extractLine(), let pending = lineContinuation {
            lineContinuation = nil
            lock.unlock()
            pending.resume(returning: lineData)
        } else {
            lock.unlock()
        }
    }

    public func serialPort(_ serialPort: ORSSerialPort, didEncounterError error: Error) {
        lock.lock()
        let pending = lineContinuation
        lineContinuation = nil
        lock.unlock()
        pending?.resume(throwing: HardwareWalletError.serialPortError(error.localizedDescription))
    }

    public func serialPortWasOpened(_ serialPort: ORSSerialPort) {
        lock.lock()
        let pending = openContinuation
        openContinuation = nil
        lock.unlock()
        pending?.resume()
    }

    public func serialPortWasClosed(_ serialPort: ORSSerialPort) {
        lock.lock()
        receiveBuffer.removeAll()
        let pending = lineContinuation
        lineContinuation = nil
        lock.unlock()
        pending?.resume(throwing: HardwareWalletError.connectionFailed("Port was closed"))
    }

    // MARK: - Private

    /// Extract a complete line from the receive buffer.
    /// Must be called while holding `lock`.
    /// Returns the line data (without the trailing newline/carriage return), or nil if no complete line is available.
    private func extractLine() -> Data? {
        guard let newlineIndex = receiveBuffer.firstIndex(of: UInt8(ascii: "\n")) else {
            return nil
        }
        var lineData = receiveBuffer[receiveBuffer.startIndex..<newlineIndex]
        receiveBuffer = Data(receiveBuffer[(newlineIndex + 1)...])
        // Strip trailing \r to handle \r\n line endings from ESP32
        if lineData.last == UInt8(ascii: "\r") {
            lineData = lineData.dropLast()
        }
        return Data(lineData)
    }
}
