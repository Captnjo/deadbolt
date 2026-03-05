use crate::models::DeadboltError;

/// Known USB VID/PID pairs for ESP32 devices.
const ESPRESSIF_VID: u16 = 0x303A;
const CP210X_VID: u16 = 0x10C4;
const CP210X_PID: u16 = 0xEA60;
const CH340_VID: u16 = 0x1A86;
const CH340_PID: u16 = 0x7523;

/// A detected serial port that may be an ESP32 device.
#[derive(Debug, Clone)]
pub struct DetectedPort {
    /// System port path (e.g., /dev/tty.usbserial-0001 or COM3)
    pub path: String,
    /// USB vendor ID
    pub vid: u16,
    /// USB product ID
    pub pid: u16,
    /// Product name if available
    pub product: Option<String>,
}

/// Scan for connected ESP32 devices by checking serial ports for known VID/PIDs.
pub fn scan() -> Result<Vec<DetectedPort>, DeadboltError> {
    let ports = serialport::available_ports()
        .map_err(|e| DeadboltError::StorageError(format!("Failed to enumerate serial ports: {e}")))?;

    let mut detected = Vec::new();

    for port in ports {
        if let serialport::SerialPortType::UsbPort(info) = &port.port_type {
            if is_esp32_device(info.vid, info.pid) {
                detected.push(DetectedPort {
                    path: port.port_name.clone(),
                    vid: info.vid,
                    pid: info.pid,
                    product: info.product.clone(),
                });
            }
        }
    }

    Ok(detected)
}

/// Check if a VID/PID pair matches known ESP32 USB-serial chips.
fn is_esp32_device(vid: u16, pid: u16) -> bool {
    // Espressif native USB (ESP32-S2, S3, C3)
    if vid == ESPRESSIF_VID {
        return true;
    }
    // Silicon Labs CP210x (common USB-UART bridge)
    if vid == CP210X_VID && pid == CP210X_PID {
        return true;
    }
    // WCH CH340 (another common USB-UART bridge)
    if vid == CH340_VID && pid == CH340_PID {
        return true;
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_esp32_device() {
        assert!(is_esp32_device(0x303A, 0x1001)); // Espressif
        assert!(is_esp32_device(0x10C4, 0xEA60)); // CP210x
        assert!(is_esp32_device(0x1A86, 0x7523)); // CH340
        assert!(!is_esp32_device(0x0000, 0x0000)); // Unknown
        assert!(!is_esp32_device(0x2341, 0x0043)); // Arduino Uno
    }

    #[test]
    fn test_scan_returns_list() {
        // Just verify it doesn't panic — may or may not find devices
        let result = scan();
        assert!(result.is_ok());
    }
}
