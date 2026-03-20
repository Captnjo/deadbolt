use std::io::{BufRead, BufReader, Write};
use std::time::Instant;

use super::types::WalletInfoDto;

/// A detected serial port that may be an Unruggable hardware wallet.
pub struct DetectedPortDto {
    pub path: String,
    pub vid: u16,
    pub pid: u16,
    pub product: String,
}

/// Scan serial ports for potential hardware wallets.
pub fn scan_hardware_wallets() -> Result<Vec<DetectedPortDto>, String> {
    let ports = serialport::available_ports().map_err(|e| e.to_string())?;
    let mut results = Vec::new();
    for port in ports {
        if let serialport::SerialPortType::UsbPort(usb) = port.port_type {
            // On macOS each USB serial shows as both /dev/cu.* and /dev/tty.*.
            // Only show cu.* (the outgoing/initiating port) to avoid duplicates.
            if port.port_name.contains("/tty.") {
                continue;
            }
            results.push(DetectedPortDto {
                path: port.port_name,
                vid: usb.vid,
                pid: usb.pid,
                product: usb.product.unwrap_or_default(),
            });
        }
    }
    Ok(results)
}

/// Read a JSON line from the port, skipping non-JSON boot messages.
fn read_json_line(reader: &mut BufReader<Box<dyn serialport::SerialPort>>) -> Result<String, String> {
    let mut line = String::new();
    loop {
        line.clear();
        reader
            .read_line(&mut line)
            .map_err(|e| format!("Failed to read response: {e}"))?;
        let trimmed = line.trim();
        // Skip boot banner lines (start with #) and empty lines
        if trimmed.starts_with('{') {
            return Ok(trimmed.to_string());
        }
    }
}

/// Send a JSON command in 64-byte chunks to avoid overflowing ESP32 USB-CDC buffer.
fn send_command(port: &mut Box<dyn serialport::SerialPort>, cmd: &str) -> Result<(), String> {
    let data = format!("{cmd}\n");
    let bytes = data.as_bytes();
    for chunk in bytes.chunks(64) {
        port.write_all(chunk)
            .map_err(|e| format!("Failed to send command: {e}"))?;
        if bytes.len() > 64 {
            std::thread::sleep(std::time::Duration::from_millis(5));
        }
    }
    port.flush().map_err(|e| format!("Failed to flush: {e}"))?;
    Ok(())
}

/// Connect to a hardware wallet, registering it in the config.
pub fn connect_hardware_wallet(
    port_path: String,
    name: String,
) -> Result<WalletInfoDto, String> {
    // Open serial port at 115200 baud with 5s read timeout
    let mut port = serialport::new(&port_path, 115_200)
        .timeout(std::time::Duration::from_secs(5))
        .open()
        .map_err(|e| format!("Failed to open port: {e}"))?;

    // Init sequence: wait for ESP32, send bare newline to reset partial state, flush
    std::thread::sleep(std::time::Duration::from_millis(500));
    port.write_all(b"\n")
        .map_err(|e| format!("Failed to send init: {e}"))?;
    std::thread::sleep(std::time::Duration::from_millis(100));

    // Drain any buffered boot messages
    let _ = port.clear(serialport::ClearBuffer::Input);

    // Send ping to verify connectivity
    send_command(&mut port, r#"{"cmd":"ping"}"#)?;
    let mut reader = BufReader::new(port.try_clone().map_err(|e| e.to_string())?);
    let ping_resp = read_json_line(&mut reader)?;

    // Parse ping response
    let ping: serde_json::Value =
        serde_json::from_str(&ping_resp).map_err(|e| format!("Invalid ping response: {e}"))?;
    if ping.get("status").and_then(|s| s.as_str()) != Some("ok") {
        let msg = ping.get("msg").and_then(|m| m.as_str()).unwrap_or("unknown error");
        return Err(format!("Ping failed: {msg}"));
    }

    // Request public key
    send_command(
        reader.get_mut(),
        r#"{"cmd":"pubkey"}"#,
    )?;
    let key_resp = read_json_line(&mut reader)?;

    let key: serde_json::Value =
        serde_json::from_str(&key_resp).map_err(|e| format!("Invalid pubkey response: {e}"))?;
    if key.get("status").and_then(|s| s.as_str()) != Some("ok") {
        let msg = key.get("msg").and_then(|m| m.as_str()).unwrap_or("unknown error");
        return Err(format!("Get pubkey failed: {msg}"));
    }

    let address = key
        .get("address")
        .and_then(|a| a.as_str())
        .ok_or("Device response missing address field")?
        .to_string();

    // Register in wallet manager
    let mgr_lock = super::wallet::manager_pub();
    let mut mgr = mgr_lock.write().map_err(|e| e.to_string())?;
    let info = mgr
        .register_hardware_wallet(&name, &address)
        .map_err(|e| e.to_string())?;
    Ok(WalletInfoDto::from_core(&info))
}

/// Generate a new BIP39 keypair on the hardware wallet.
/// Returns the 12 mnemonic words for one-time display.
/// Requires physical BOOT button confirmation on the device.
pub fn generate_hardware_keypair(port_path: String) -> Result<Vec<String>, String> {
    let mut port = serialport::new(&port_path, 115_200)
        .timeout(std::time::Duration::from_secs(5))
        .open()
        .map_err(|e| format!("Failed to open port: {e}"))?;

    // Init sequence (same as connect_hardware_wallet)
    std::thread::sleep(std::time::Duration::from_millis(500));
    port.write_all(b"\n").map_err(|e| format!("Failed to send init: {e}"))?;
    std::thread::sleep(std::time::Duration::from_millis(100));
    let _ = port.clear(serialport::ClearBuffer::Input);

    // Send generate command
    send_command(&mut port, r#"{"cmd":"generate"}"#)?;

    let mut reader = BufReader::new(port.try_clone().map_err(|e| e.to_string())?);

    // Read responses — may get "generating" status first while awaiting button hold
    let start = Instant::now();
    let timeout = std::time::Duration::from_secs(60);
    loop {
        if start.elapsed() > timeout {
            return Err("Generate timed out (60s)".to_string());
        }
        match read_json_line(&mut reader) {
            Ok(line) => {
                let resp: serde_json::Value = serde_json::from_str(&line)
                    .map_err(|e| format!("Invalid JSON: {e}"))?;
                let status = resp.get("status").and_then(|s| s.as_str()).unwrap_or("");
                match status {
                    "generating" => continue,
                    "ok" => {
                        let words: Vec<String> = resp.get("words")
                            .and_then(|w| w.as_array())
                            .ok_or("Missing words in response")?
                            .iter()
                            .filter_map(|v| v.as_str().map(String::from))
                            .collect();
                        if words.len() != 12 {
                            return Err(format!("Expected 12 words, got {}", words.len()));
                        }
                        // Note: wallet registration happens in Flutter layer after mnemonic quiz
                        return Ok(words);
                    }
                    "error" => {
                        let msg = resp.get("msg").and_then(|m| m.as_str()).unwrap_or("unknown");
                        return Err(format!("Generate failed: {msg}"));
                    }
                    _ => continue,
                }
            }
            Err(_) => {
                // Read timeout — keep waiting for button press
                if start.elapsed() > timeout {
                    return Err("Generate timed out".to_string());
                }
                continue;
            }
        }
    }
}

/// Factory reset the hardware wallet. Erases entire NVS partition.
/// Requires physical BOOT button confirmation (5 seconds).
/// Device will reboot after reset.
pub fn factory_reset_hardware(port_path: String) -> Result<(), String> {
    let mut port = serialport::new(&port_path, 115_200)
        .timeout(std::time::Duration::from_secs(5))
        .open()
        .map_err(|e| format!("Failed to open port: {e}"))?;

    std::thread::sleep(std::time::Duration::from_millis(500));
    port.write_all(b"\n").map_err(|e| format!("Failed to send init: {e}"))?;
    std::thread::sleep(std::time::Duration::from_millis(100));
    let _ = port.clear(serialport::ClearBuffer::Input);

    send_command(&mut port, r#"{"cmd":"reset"}"#)?;

    let mut reader = BufReader::new(port.try_clone().map_err(|e| e.to_string())?);
    let start = Instant::now();
    let timeout = std::time::Duration::from_secs(30);
    loop {
        if start.elapsed() > timeout {
            return Err("Factory reset timed out".to_string());
        }
        match read_json_line(&mut reader) {
            Ok(line) => {
                let resp: serde_json::Value = serde_json::from_str(&line)
                    .map_err(|e| format!("Invalid JSON: {e}"))?;
                let status = resp.get("status").and_then(|s| s.as_str()).unwrap_or("");
                match status {
                    "pending" => continue,
                    "ok" => return Ok(()),
                    "error" => {
                        let msg = resp.get("msg").and_then(|m| m.as_str()).unwrap_or("unknown");
                        return Err(format!("Reset failed: {msg}"));
                    }
                    _ => continue,
                }
            }
            Err(_) => continue,
        }
    }
}

/// Verify the hardware wallet's entropy source is working correctly.
pub fn check_hardware_entropy(port_path: String) -> Result<(), String> {
    let mut port = serialport::new(&port_path, 115_200)
        .timeout(std::time::Duration::from_secs(5))
        .open()
        .map_err(|e| format!("Failed to open port: {e}"))?;

    std::thread::sleep(std::time::Duration::from_millis(500));
    port.write_all(b"\n").map_err(|e| format!("Failed to send init: {e}"))?;
    std::thread::sleep(std::time::Duration::from_millis(100));
    let _ = port.clear(serialport::ClearBuffer::Input);

    send_command(&mut port, r#"{"cmd":"entropy_check"}"#)?;
    let mut reader = BufReader::new(port.try_clone().map_err(|e| e.to_string())?);
    let resp_line = read_json_line(&mut reader)?;
    let resp: serde_json::Value = serde_json::from_str(&resp_line)
        .map_err(|e| format!("Invalid JSON: {e}"))?;
    if resp.get("status").and_then(|s| s.as_str()) == Some("ok") {
        Ok(())
    } else {
        let msg = resp.get("msg").and_then(|m| m.as_str()).unwrap_or("entropy_check_failed");
        Err(format!("Entropy check failed: {msg}"))
    }
}

/// Get the public key from a connected hardware wallet without full registration.
/// Used for auto-connect pubkey verification (HWLT-03).
pub fn get_hardware_pubkey(port_path: String) -> Result<String, String> {
    let mut port = serialport::new(&port_path, 115_200)
        .timeout(std::time::Duration::from_secs(5))
        .open()
        .map_err(|e| format!("Failed to open port: {e}"))?;

    std::thread::sleep(std::time::Duration::from_millis(500));
    port.write_all(b"\n").map_err(|e| format!("Failed to send init: {e}"))?;
    std::thread::sleep(std::time::Duration::from_millis(100));
    let _ = port.clear(serialport::ClearBuffer::Input);

    send_command(&mut port, r#"{"cmd":"ping"}"#)?;
    let mut reader = BufReader::new(port.try_clone().map_err(|e| e.to_string())?);
    let ping_resp = read_json_line(&mut reader)?;
    let ping: serde_json::Value = serde_json::from_str(&ping_resp)
        .map_err(|e| format!("Invalid ping: {e}"))?;
    if ping.get("status").and_then(|s| s.as_str()) != Some("ok") {
        return Err("Ping failed".to_string());
    }

    send_command(reader.get_mut(), r#"{"cmd":"pubkey"}"#)?;
    let key_resp = read_json_line(&mut reader)?;
    let key: serde_json::Value = serde_json::from_str(&key_resp)
        .map_err(|e| format!("Invalid pubkey response: {e}"))?;
    if key.get("status").and_then(|s| s.as_str()) != Some("ok") {
        let msg = key.get("msg").and_then(|m| m.as_str()).unwrap_or("unknown");
        return Err(format!("Pubkey failed: {msg}"));
    }

    key.get("address")
        .and_then(|a| a.as_str())
        .map(String::from)
        .ok_or("Missing address field".to_string())
}
