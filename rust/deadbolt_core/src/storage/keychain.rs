use security_framework::passwords::{
    delete_generic_password, get_generic_password, set_generic_password,
};

use crate::models::DeadboltError;

use super::SecureStorage;

const SERVICE: &str = "com.deadbolt.wallet";

/// macOS/iOS Keychain storage backend.
/// Stores vault encryption keys (not raw seeds) in the system Keychain.
/// Uses the same service name as the Swift app for migration compatibility.
pub struct KeychainStorage;

impl KeychainStorage {
    pub fn new() -> Self {
        Self
    }
}

impl SecureStorage for KeychainStorage {
    fn store_vault_key(&self, key: &[u8; 32], address: &str) -> Result<(), DeadboltError> {
        // Delete existing first (ignore errors)
        let _ = delete_generic_password(SERVICE, address);

        set_generic_password(SERVICE, address, key)
            .map_err(|e| DeadboltError::StorageError(e.to_string()))
    }

    fn retrieve_vault_key(&self, address: &str) -> Result<[u8; 32], DeadboltError> {
        let data = get_generic_password(SERVICE, address).map_err(|e| {
            if e.to_string().contains("-25300") {
                DeadboltError::StorageItemNotFound
            } else {
                DeadboltError::StorageError(e.to_string())
            }
        })?;

        if data.len() != 32 {
            return Err(DeadboltError::StorageError(format!(
                "Vault key has unexpected length: {}",
                data.len()
            )));
        }

        let mut key = [0u8; 32];
        key.copy_from_slice(&data);
        Ok(key)
    }

    fn delete_vault_key(&self, address: &str) -> Result<(), DeadboltError> {
        let _ = delete_generic_password(SERVICE, address);
        Ok(())
    }

    fn list_addresses(&self) -> Result<Vec<String>, DeadboltError> {
        // security-framework doesn't have a direct "list all" API.
        // The wallet manager tracks addresses in config.json.
        // Full implementation could use SecItemCopyMatching with kSecMatchLimitAll.
        Ok(Vec::new())
    }
}

/// Check if a raw seed (legacy format from Swift app) exists in Keychain.
/// Used for migration detection.
pub fn has_legacy_seed(address: &str) -> bool {
    // The old Swift app stored raw 32-byte seeds under the same service name.
    // If the data is exactly 32 bytes and we haven't migrated yet, it's a legacy entry.
    get_generic_password(SERVICE, address).is_ok()
}

/// Read a legacy raw seed from Keychain (for migration).
pub fn read_legacy_seed(address: &str) -> Result<[u8; 32], DeadboltError> {
    let data = get_generic_password(SERVICE, address).map_err(|e| {
        if e.to_string().contains("-25300") {
            DeadboltError::StorageItemNotFound
        } else {
            DeadboltError::StorageError(e.to_string())
        }
    })?;

    if data.len() != 32 {
        return Err(DeadboltError::StorageError(format!(
            "Legacy seed has unexpected length: {}",
            data.len()
        )));
    }

    let mut seed = [0u8; 32];
    seed.copy_from_slice(&data);
    Ok(seed)
}

/// Legacy mnemonic service name from Swift app.
const LEGACY_MNEMONIC_SERVICE: &str = "com.deadbolt.wallet.mnemonic";

/// Read a legacy mnemonic from Keychain (for migration).
pub fn read_legacy_mnemonic(address: &str) -> Result<Option<Vec<String>>, DeadboltError> {
    match get_generic_password(LEGACY_MNEMONIC_SERVICE, address) {
        Ok(data) => {
            let phrase = String::from_utf8(data)
                .map_err(|e| DeadboltError::StorageError(e.to_string()))?;
            Ok(Some(phrase.split_whitespace().map(String::from).collect()))
        }
        Err(e) => {
            if e.to_string().contains("-25300") {
                Ok(None)
            } else {
                Err(DeadboltError::StorageError(e.to_string()))
            }
        }
    }
}

/// Delete legacy entries after migration.
pub fn delete_legacy_entries(address: &str) {
    let _ = delete_generic_password(SERVICE, address);
    let _ = delete_generic_password(LEGACY_MNEMONIC_SERVICE, address);
}
