import Foundation

/// Abstraction over a serial port for testability.
/// Real implementation wraps ORSSerialPort; mock replaces it in tests.
public protocol SerialPortProtocol: Sendable {
    /// Open the serial port for communication.
    func open() async throws

    /// Close the serial port.
    func close()

    /// Whether the port is currently open.
    var isOpen: Bool { get }

    /// Send raw data over the serial port.
    func send(_ data: Data) async throws

    /// Receive a complete line (newline-delimited) from the serial port.
    /// - Parameter timeout: Maximum time to wait for a response in seconds.
    /// - Returns: The received data (including trailing newline stripped).
    func receiveLine(timeout: TimeInterval) async throws -> Data

    /// Discard any data currently in the receive buffer.
    func flushReceiveBuffer()
}
