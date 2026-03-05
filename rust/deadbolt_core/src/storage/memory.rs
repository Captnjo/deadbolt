use std::collections::HashMap;
use std::sync::Mutex;

use crate::models::DeadboltError;

use super::SecureStorage;

/// In-memory storage backend for testing.
pub struct MemoryStorage {
    vault_keys: Mutex<HashMap<String, [u8; 32]>>,
}

impl MemoryStorage {
    pub fn new() -> Self {
        Self {
            vault_keys: Mutex::new(HashMap::new()),
        }
    }
}

impl SecureStorage for MemoryStorage {
    fn store_vault_key(&self, key: &[u8; 32], address: &str) -> Result<(), DeadboltError> {
        self.vault_keys
            .lock()
            .unwrap()
            .insert(address.to_string(), *key);
        Ok(())
    }

    fn retrieve_vault_key(&self, address: &str) -> Result<[u8; 32], DeadboltError> {
        self.vault_keys
            .lock()
            .unwrap()
            .get(address)
            .copied()
            .ok_or(DeadboltError::StorageItemNotFound)
    }

    fn delete_vault_key(&self, address: &str) -> Result<(), DeadboltError> {
        self.vault_keys.lock().unwrap().remove(address);
        Ok(())
    }

    fn list_addresses(&self) -> Result<Vec<String>, DeadboltError> {
        Ok(self.vault_keys.lock().unwrap().keys().cloned().collect())
    }
}
