use std::sync::Mutex;

use crate::crypto::signer::TransactionSigner;
use crate::crypto::SolanaPublicKey;
use crate::models::DeadboltError;

use super::esp32_bridge::Esp32Bridge;

/// TransactionSigner implementation that delegates signing to an ESP32 hardware wallet.
/// The private key never touches the host machine.
pub struct Esp32Signer {
    bridge: Mutex<Esp32Bridge>,
    pubkey: SolanaPublicKey,
}

impl Esp32Signer {
    /// Create a signer from a connected ESP32 bridge.
    pub fn new(bridge: Esp32Bridge) -> Result<Self, DeadboltError> {
        let pubkey = bridge
            .public_key()
            .ok_or_else(|| {
                DeadboltError::StorageError("ESP32 bridge has no public key".into())
            })?
            .clone();

        Ok(Self {
            bridge: Mutex::new(bridge),
            pubkey,
        })
    }
}

impl TransactionSigner for Esp32Signer {
    fn public_key(&self) -> &SolanaPublicKey {
        &self.pubkey
    }

    fn sign(&self, message: &[u8]) -> Result<[u8; 64], DeadboltError> {
        let mut bridge = self.bridge.lock().map_err(|e| {
            DeadboltError::SigningError(format!("Failed to lock ESP32 bridge: {e}"))
        })?;
        bridge.sign(message)
    }
}
