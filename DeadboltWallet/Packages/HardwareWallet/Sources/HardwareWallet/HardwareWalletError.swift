import Foundation

/// Errors specific to hardware wallet operations
public enum HardwareWalletError: LocalizedError {
    /// No ESP32 device found on any serial port
    case deviceNotFound
    /// Failed to open or configure the serial port
    case connectionFailed(String)
    /// The device did not respond within the expected time
    case timeout
    /// The user rejected the signing request on the device
    case rejected
    /// The device returned a response that could not be parsed
    case invalidResponse(String)
    /// A low-level serial port error occurred
    case serialPortError(String)

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "No ESP32 hardware wallet found. Check USB connection."
        case .connectionFailed(let detail):
            return "Connection failed: \(detail)"
        case .timeout:
            return "Hardware wallet did not respond in time."
        case .rejected:
            return "Transaction was rejected on the hardware wallet."
        case .invalidResponse(let detail):
            return "Invalid response from hardware wallet: \(detail)"
        case .serialPortError(let detail):
            return "Serial port error: \(detail)"
        }
    }
}
