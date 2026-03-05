use secret_service::EncryptionType;
use secret_service::SecretService;

use crate::models::DeadboltError;

use super::SecureStorage;

const COLLECTION: &str = "deadbolt";
const LABEL_PREFIX: &str = "Deadbolt Wallet Key: ";

/// Linux Secret Service storage backend.
/// Uses GNOME Keyring or KDE Wallet via the D-Bus Secret Service API
/// to store vault encryption keys.
pub struct SecretServiceStorage;

impl SecretServiceStorage {
    pub fn new() -> Self {
        Self
    }

    fn get_service() -> Result<SecretService<'static>, DeadboltError> {
        SecretService::connect(EncryptionType::Dh)
            .map_err(|e| DeadboltError::StorageError(format!("Secret Service connect failed: {e}")))
    }
}

impl SecureStorage for SecretServiceStorage {
    fn store_vault_key(&self, key: &[u8; 32], address: &str) -> Result<(), DeadboltError> {
        let ss = Self::get_service()?;
        let collection = ss
            .get_default_collection()
            .map_err(|e| DeadboltError::StorageError(format!("Get collection failed: {e}")))?;

        // Unlock collection if locked
        let _ = collection.unlock();

        let label = format!("{LABEL_PREFIX}{address}");
        let attributes = vec![
            ("application", "deadbolt"),
            ("address", address),
        ];

        // Delete existing entry first
        if let Ok(items) = collection.search_items(attributes.clone()) {
            for item in items {
                let _ = item.delete();
            }
        }

        collection
            .create_item(
                &label,
                attributes,
                key,
                true, // replace existing
                "application/octet-stream",
            )
            .map_err(|e| DeadboltError::StorageError(format!("Store failed: {e}")))?;

        Ok(())
    }

    fn retrieve_vault_key(&self, address: &str) -> Result<[u8; 32], DeadboltError> {
        let ss = Self::get_service()?;
        let collection = ss
            .get_default_collection()
            .map_err(|e| DeadboltError::StorageError(format!("Get collection failed: {e}")))?;

        let _ = collection.unlock();

        let attributes = vec![
            ("application", "deadbolt"),
            ("address", address),
        ];

        let items = collection
            .search_items(attributes)
            .map_err(|e| DeadboltError::StorageError(format!("Search failed: {e}")))?;

        let item = items.first().ok_or(DeadboltError::StorageItemNotFound)?;

        let secret = item
            .get_secret()
            .map_err(|e| DeadboltError::StorageError(format!("Get secret failed: {e}")))?;

        if secret.len() != 32 {
            return Err(DeadboltError::StorageError(format!(
                "Vault key has unexpected length: {}",
                secret.len()
            )));
        }

        let mut key = [0u8; 32];
        key.copy_from_slice(&secret);
        Ok(key)
    }

    fn delete_vault_key(&self, address: &str) -> Result<(), DeadboltError> {
        let ss = Self::get_service()?;
        let collection = ss
            .get_default_collection()
            .map_err(|e| DeadboltError::StorageError(format!("Get collection failed: {e}")))?;

        let _ = collection.unlock();

        let attributes = vec![
            ("application", "deadbolt"),
            ("address", address),
        ];

        if let Ok(items) = collection.search_items(attributes) {
            for item in items {
                let _ = item.delete();
            }
        }

        Ok(())
    }

    fn list_addresses(&self) -> Result<Vec<String>, DeadboltError> {
        // Addresses tracked in config.json
        Ok(Vec::new())
    }
}
