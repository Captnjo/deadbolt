use std::io::{BufRead, BufReader, Write};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

use crate::crypto::SolanaPublicKey;
use crate::models::DeadboltError;

const BAUD_RATE: u32 = 115_200;
const READ_TIMEOUT: Duration = Duration::from_millis(500);
const SIGN_TIMEOUT: Duration = Duration::from_secs(30);
/// PBKDF2 on ESP32 takes up to 30s, plus 5s button hold.
const GENERATE_TIMEOUT: Duration = Duration::from_secs(60);

/// Status events emitted during ESP32 operations.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Esp32Event {
    Connected { address: String },
    Disconnected,
    AwaitingConfirmation,
    Signed,
    Error(String),
}

/// JSON command sent to ESP32.
#[derive(Serialize)]
struct Command {
    cmd: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    payload: Option<String>,
}

/// JSON response from ESP32.
#[derive(Deserialize, Debug)]
struct Response {
    status: String,
    #[serde(default)]
    msg: Option<String>,
    #[serde(default)]
    pubkey: Option<String>,
    #[serde(default)]
    address: Option<String>,
    #[serde(default)]
    signature: Option<String>,
    #[serde(default)]
    words: Option<Vec<String>>,
}

/// Connection to an ESP32 hardware wallet over serial.
pub struct Esp32Bridge {
    port: Box<dyn serialport::SerialPort>,
    pubkey: Option<SolanaPublicKey>,
    address: Option<String>,
}

impl Esp32Bridge {
    /// Connect to an ESP32 device at the given serial port path.
    pub fn connect(port_path: &str) -> Result<Self, DeadboltError> {
        let port = serialport::new(port_path, BAUD_RATE)
            .timeout(READ_TIMEOUT)
            .open()
            .map_err(|e| DeadboltError::StorageError(format!("Failed to open serial port: {e}")))?;

        let mut bridge = Self {
            port,
            pubkey: None,
            address: None,
        };

        // Ping to verify connection
        bridge.ping()?;

        // Get public key
        bridge.fetch_pubkey()?;

        Ok(bridge)
    }

    /// Send a ping and verify we get a pong.
    pub fn ping(&mut self) -> Result<(), DeadboltError> {
        let resp = self.send_command("ping", None)?;
        if resp.status != "ok" || resp.msg.as_deref() != Some("pong") {
            return Err(DeadboltError::StorageError(
                "ESP32 ping failed: unexpected response".into(),
            ));
        }
        Ok(())
    }

    /// Get the public key from the ESP32.
    pub fn public_key(&self) -> Option<&SolanaPublicKey> {
        self.pubkey.as_ref()
    }

    /// Get the Base58 address from the ESP32.
    pub fn address(&self) -> Option<&str> {
        self.address.as_deref()
    }

    /// Request the ESP32 to sign a message.
    /// The ESP32 will pulse its LED and wait for the user to press BOOT.
    /// Returns the 64-byte Ed25519 signature.
    pub fn sign(&mut self, message: &[u8]) -> Result<[u8; 64], DeadboltError> {
        let payload = hex::encode(message);

        // Send sign command
        self.write_json(&Command {
            cmd: "sign".to_string(),
            payload: Some(payload),
        })?;

        // Wait for response — may be "pending" first, then "signed"
        let start = Instant::now();
        loop {
            if start.elapsed() > SIGN_TIMEOUT {
                return Err(DeadboltError::SigningError(
                    "ESP32 sign timed out (30s)".into(),
                ));
            }

            match self.read_response() {
                Ok(resp) => {
                    match resp.status.as_str() {
                        "pending" => {
                            // ESP32 is waiting for BOOT button press
                            continue;
                        }
                        "signed" => {
                            let sig_hex = resp.signature.ok_or_else(|| {
                                DeadboltError::SigningError(
                                    "ESP32 signed response missing signature".into(),
                                )
                            })?;
                            let sig_bytes = hex::decode(&sig_hex).map_err(|e| {
                                DeadboltError::SigningError(format!(
                                    "Invalid signature hex: {e}"
                                ))
                            })?;
                            if sig_bytes.len() != 64 {
                                return Err(DeadboltError::SigningError(format!(
                                    "Signature has wrong length: {}",
                                    sig_bytes.len()
                                )));
                            }
                            let mut sig = [0u8; 64];
                            sig.copy_from_slice(&sig_bytes);
                            return Ok(sig);
                        }
                        "error" => {
                            let msg = resp.msg.unwrap_or_else(|| "unknown error".into());
                            return Err(DeadboltError::SigningError(format!(
                                "ESP32 sign error: {msg}"
                            )));
                        }
                        other => {
                            return Err(DeadboltError::SigningError(format!(
                                "Unexpected ESP32 status: {other}"
                            )));
                        }
                    }
                }
                Err(_) => {
                    // Read timeout — retry
                    continue;
                }
            }
        }
    }

    /// Send generate command to create a new BIP39 keypair.
    /// Requires physical BOOT button confirmation (5 seconds).
    /// Returns 12 mnemonic words on success.
    pub fn generate(&mut self) -> Result<Vec<String>, DeadboltError> {
        self.write_json(&Command { cmd: "generate".to_string(), payload: None })?;

        let start = Instant::now();
        loop {
            if start.elapsed() > GENERATE_TIMEOUT {
                return Err(DeadboltError::SigningError("ESP32 generate timed out (60s)".into()));
            }
            match self.read_response() {
                Ok(resp) => match resp.status.as_str() {
                    "generating" => continue, // Firmware is waiting for BOOT hold
                    "ok" => {
                        let words = resp.words.ok_or_else(|| {
                            DeadboltError::StorageError("Generate response missing words field".into())
                        })?;
                        if words.len() != 12 {
                            return Err(DeadboltError::StorageError(format!(
                                "Expected 12 mnemonic words, got {}", words.len()
                            )));
                        }
                        // Also update stored pubkey/address
                        if let Some(hex_pk) = resp.pubkey {
                            let pk_bytes = hex::decode(&hex_pk).map_err(|e| {
                                DeadboltError::StorageError(format!("Invalid pubkey hex: {e}"))
                            })?;
                            if pk_bytes.len() == 32 {
                                let mut pk = [0u8; 32];
                                pk.copy_from_slice(&pk_bytes);
                                self.pubkey = Some(SolanaPublicKey::from_bytes(&pk)?);
                            }
                        }
                        self.address = resp.address;
                        return Ok(words);
                    }
                    "error" => {
                        let msg = resp.msg.unwrap_or_else(|| "unknown".into());
                        return Err(DeadboltError::StorageError(format!("ESP32 generate error: {msg}")));
                    }
                    other => {
                        return Err(DeadboltError::StorageError(format!(
                            "Unexpected generate status: {other}"
                        )));
                    }
                },
                Err(_) => continue, // Read timeout, retry
            }
        }
    }

    /// Send factory reset command. Requires 5-second BOOT button hold.
    /// Device will reboot after successful reset.
    pub fn factory_reset(&mut self) -> Result<(), DeadboltError> {
        self.write_json(&Command { cmd: "reset".to_string(), payload: None })?;

        let start = Instant::now();
        loop {
            if start.elapsed() > GENERATE_TIMEOUT {
                return Err(DeadboltError::StorageError("ESP32 reset timed out".into()));
            }
            match self.read_response() {
                Ok(resp) => match resp.status.as_str() {
                    "pending" => continue,
                    "ok" => return Ok(()),
                    "error" => {
                        let msg = resp.msg.unwrap_or_else(|| "unknown".into());
                        return Err(DeadboltError::StorageError(format!("ESP32 reset error: {msg}")));
                    }
                    other => {
                        return Err(DeadboltError::StorageError(format!(
                            "Unexpected reset status: {other}"
                        )));
                    }
                },
                Err(_) => continue,
            }
        }
    }

    /// Send entropy check command. Returns Ok(()) if entropy source is valid.
    pub fn check_entropy(&mut self) -> Result<(), DeadboltError> {
        let resp = self.send_command("entropy_check", None)?;
        if resp.status == "ok" {
            Ok(())
        } else {
            let msg = resp.msg.unwrap_or_else(|| "entropy_check_failed".into());
            Err(DeadboltError::StorageError(format!("Entropy check failed: {msg}")))
        }
    }

    // --- Internal methods ---

    fn fetch_pubkey(&mut self) -> Result<(), DeadboltError> {
        let resp = self.send_command("pubkey", None)?;
        if resp.status != "ok" {
            return Err(DeadboltError::StorageError(
                "ESP32 pubkey request failed".into(),
            ));
        }

        let hex_pubkey = resp.pubkey.ok_or_else(|| {
            DeadboltError::StorageError("ESP32 pubkey response missing pubkey field".into())
        })?;

        let pubkey_bytes = hex::decode(&hex_pubkey)
            .map_err(|e| DeadboltError::StorageError(format!("Invalid pubkey hex: {e}")))?;

        if pubkey_bytes.len() != 32 {
            return Err(DeadboltError::StorageError(format!(
                "ESP32 pubkey has wrong length: {}",
                pubkey_bytes.len()
            )));
        }

        let mut pk = [0u8; 32];
        pk.copy_from_slice(&pubkey_bytes);
        self.pubkey = Some(SolanaPublicKey::from_bytes(&pk)?);
        self.address = resp.address;

        Ok(())
    }

    fn send_command(
        &mut self,
        cmd: &str,
        payload: Option<String>,
    ) -> Result<Response, DeadboltError> {
        self.write_json(&Command {
            cmd: cmd.to_string(),
            payload,
        })?;
        self.read_response()
    }

    fn write_json<T: Serialize>(&mut self, value: &T) -> Result<(), DeadboltError> {
        let json = serde_json::to_string(value)
            .map_err(|e| DeadboltError::StorageError(format!("JSON serialize failed: {e}")))?;

        // Write in chunks to avoid overwhelming the ESP32 USB-CDC buffer.
        // A 5ms delay between chunks prevents buffer overflow on large payloads
        // (e.g. sign commands with hex-encoded transaction messages).
        let bytes = json.as_bytes();
        for chunk in bytes.chunks(64) {
            self.port.write_all(chunk).map_err(|e| {
                DeadboltError::StorageError(format!("Serial write failed: {e}"))
            })?;
            self.port.flush().map_err(|e| {
                DeadboltError::StorageError(format!("Serial flush failed: {e}"))
            })?;
            if bytes.len() > 64 {
                std::thread::sleep(Duration::from_millis(5));
            }
        }

        // Send newline delimiter
        self.port.write_all(b"\n").map_err(|e| {
            DeadboltError::StorageError(format!("Serial write newline failed: {e}"))
        })?;
        self.port.flush().map_err(|e| {
            DeadboltError::StorageError(format!("Serial flush failed: {e}"))
        })?;

        Ok(())
    }

    fn read_response(&mut self) -> Result<Response, DeadboltError> {
        let mut reader = BufReader::new(&mut self.port);
        let mut line = String::new();

        reader.read_line(&mut line).map_err(|e| {
            DeadboltError::StorageError(format!("Serial read failed: {e}"))
        })?;

        let line = line.trim();
        if line.is_empty() {
            return Err(DeadboltError::StorageError("Empty response from ESP32".into()));
        }

        serde_json::from_str(line)
            .map_err(|e| DeadboltError::StorageError(format!("Invalid JSON from ESP32: {e}")))
    }
}
