import Foundation
import ORSSerial

/// Detects ESP32 hardware wallet devices connected via USB serial.
///
/// Monitors the system for ESP32 serial port connections and disconnections.
/// Uses ORSSerialPortManager to observe available ports and filters for
/// known ESP32 USB-to-serial adapter patterns.
public actor ESP32Detector {

    // MARK: - Types

    /// Notification posted when an ESP32 device is connected.
    public static let deviceConnectedNotification = Notification.Name("ESP32DeviceConnected")

    /// Notification posted when an ESP32 device is disconnected.
    public static let deviceDisconnectedNotification = Notification.Name("ESP32DeviceDisconnected")

    /// Key in notification userInfo containing the port path (String).
    public static let portPathKey = "portPath"

    // MARK: - Properties

    /// Currently detected ESP32 serial port paths.
    public private(set) var detectedPorts: [String] = []

    /// Whether the detector is actively monitoring for devices.
    public private(set) var isMonitoring = false

    private let observer: PortObserver

    // MARK: - Known ESP32 port patterns

    /// Port name patterns that indicate an ESP32 or compatible USB-to-serial adapter.
    /// Covers: CP210x (Silicon Labs), CH340/CH9102 (WCH), FTDI, and generic USB serial.
    private static let knownPatterns: [String] = [
        "cu.usbserial",
        "cu.SLAB_USBtoUART",
        "cu.wchusbserial",
        "cu.usbmodem",
        "cu.CP210",
        "cu.CH910",
    ]

    // MARK: - Init

    public init() {
        self.observer = PortObserver()
    }

    // MARK: - Public API

    /// Start monitoring for ESP32 device connections and disconnections.
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Do initial scan
        let ports = Self.scanForESP32Ports()
        detectedPorts = ports

        // Start observing connect/disconnect
        observer.onPortsChanged = { [weak self] in
            guard let self else { return }
            Task {
                await self.handlePortsChanged()
            }
        }
        observer.startObserving()
    }

    /// Stop monitoring for device changes.
    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        observer.stopObserving()
        observer.onPortsChanged = nil
    }

    /// Perform a one-time scan for connected ESP32 devices.
    /// Returns the paths of any detected ESP32 serial ports.
    public func scan() -> [String] {
        let ports = Self.scanForESP32Ports()
        detectedPorts = ports
        return ports
    }

    // MARK: - Internal

    /// Check whether a given port path matches known ESP32 patterns.
    static func matchesESP32Pattern(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return knownPatterns.contains { pattern in
            name.contains(pattern)
        }
    }

    /// Scan all available serial ports and return paths matching ESP32 patterns.
    static func scanForESP32Ports() -> [String] {
        let manager = ORSSerialPortManager.shared()
        let ports = manager.availablePorts
        return ports
            .map { $0.path }
            .filter { matchesESP32Pattern($0) }
    }

    private func handlePortsChanged() {
        let newPorts = Self.scanForESP32Ports()
        let previousPorts = Set(detectedPorts)
        let currentPorts = Set(newPorts)

        // Detect newly connected
        let connected = currentPorts.subtracting(previousPorts)
        for path in connected {
            NotificationCenter.default.post(
                name: Self.deviceConnectedNotification,
                object: nil,
                userInfo: [Self.portPathKey: path]
            )
        }

        // Detect disconnected
        let disconnected = previousPorts.subtracting(currentPorts)
        for path in disconnected {
            NotificationCenter.default.post(
                name: Self.deviceDisconnectedNotification,
                object: nil,
                userInfo: [Self.portPathKey: path]
            )
        }

        detectedPorts = newPorts
    }
}

// MARK: - Port Observer (NSObject delegate bridge)

/// Bridges ORSSerialPortManager KVO notifications into a closure-based callback.
private final class PortObserver: NSObject, @unchecked Sendable {
    var onPortsChanged: (() -> Void)?

    func startObserving() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(portsDidChange(_:)),
            name: .ORSSerialPortsWereConnected,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(portsDidChange(_:)),
            name: .ORSSerialPortsWereDisconnected,
            object: nil
        )
    }

    func stopObserving() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func portsDidChange(_ notification: Notification) {
        onPortsChanged?()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
