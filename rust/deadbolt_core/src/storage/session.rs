use std::collections::HashMap;
use std::sync::Mutex;

use zeroize::Zeroize;

use crate::crypto::signer::{SoftwareSigner, TransactionSigner};
use crate::crypto::vault;
use crate::models::DeadboltError;

/// Manages the in-memory session state for unlocked wallets.
/// Seeds are held in memory only while unlocked and zeroized on lock.
pub struct SessionManager {
    /// Map of address -> decrypted seed (only while unlocked)
    sessions: Mutex<HashMap<String, [u8; 32]>>,
}

impl SessionManager {
    pub fn new() -> Self {
        Self {
            sessions: Mutex::new(HashMap::new()),
        }
    }

    /// Unlock a wallet by decrypting its vault with the provided key.
    /// The vault_data is the encrypted vault file contents.
    /// The key is the 32-byte vault encryption key from platform secure storage.
    pub fn unlock_with_key(
        &self,
        address: &str,
        vault_data: &[u8],
        vault_key: &[u8; 32],
    ) -> Result<(), DeadboltError> {
        let plaintext = vault::decrypt_with_key(vault_data, vault_key)?;

        if plaintext.len() != 32 {
            return Err(DeadboltError::VaultError(format!(
                "Decrypted seed has unexpected length: {}",
                plaintext.len()
            )));
        }

        let mut seed = [0u8; 32];
        seed.copy_from_slice(&plaintext);

        // Verify the seed produces the expected address
        let signer = SoftwareSigner::from_seed(&seed)?;
        if signer.public_key().to_base58() != address {
            seed.zeroize();
            return Err(DeadboltError::VaultError(
                "Decrypted seed does not match wallet address".into(),
            ));
        }

        self.sessions
            .lock()
            .unwrap()
            .insert(address.to_string(), seed);
        Ok(())
    }

    /// Unlock a wallet by decrypting its vault with a password.
    pub fn unlock_with_password(
        &self,
        address: &str,
        vault_data: &[u8],
        password: &[u8],
        strength: vault::KdfStrength,
    ) -> Result<(), DeadboltError> {
        let plaintext = vault::decrypt(vault_data, password, strength)?;

        if plaintext.len() != 32 {
            return Err(DeadboltError::VaultError(format!(
                "Decrypted seed has unexpected length: {}",
                plaintext.len()
            )));
        }

        let mut seed = [0u8; 32];
        seed.copy_from_slice(&plaintext);

        let signer = SoftwareSigner::from_seed(&seed)?;
        if signer.public_key().to_base58() != address {
            seed.zeroize();
            return Err(DeadboltError::VaultError(
                "Decrypted seed does not match wallet address".into(),
            ));
        }

        self.sessions
            .lock()
            .unwrap()
            .insert(address.to_string(), seed);
        Ok(())
    }

    /// Lock a wallet, zeroizing its seed from memory.
    pub fn lock(&self, address: &str) {
        let mut sessions = self.sessions.lock().unwrap();
        if let Some(seed) = sessions.get_mut(address) {
            seed.zeroize();
        }
        sessions.remove(address);
    }

    /// Lock all wallets.
    pub fn lock_all(&self) {
        let mut sessions = self.sessions.lock().unwrap();
        for seed in sessions.values_mut() {
            seed.zeroize();
        }
        sessions.clear();
    }

    /// Check if a wallet is unlocked.
    pub fn is_unlocked(&self, address: &str) -> bool {
        self.sessions.lock().unwrap().contains_key(address)
    }

    /// Get a signer for an unlocked wallet. Returns error if locked.
    pub fn get_signer(&self, address: &str) -> Result<SoftwareSigner, DeadboltError> {
        let sessions = self.sessions.lock().unwrap();
        let seed = sessions
            .get(address)
            .ok_or(DeadboltError::NoWalletLoaded)?;
        SoftwareSigner::from_seed(seed)
    }
}

impl Drop for SessionManager {
    fn drop(&mut self) {
        // Zeroize all seeds on drop
        if let Ok(mut sessions) = self.sessions.lock() {
            for seed in sessions.values_mut() {
                seed.zeroize();
            }
            sessions.clear();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::vault;

    fn test_seed_and_address() -> ([u8; 32], String) {
        let seed = [0x01u8; 32];
        let signer = SoftwareSigner::from_seed(&seed).unwrap();
        let address = signer.public_key().to_base58();
        (seed, address)
    }

    #[test]
    fn test_unlock_lock_lifecycle() {
        let (seed, address) = test_seed_and_address();
        let key = vault::generate_vault_key().unwrap();
        let vault_data = vault::encrypt_with_key(&seed, &key).unwrap();

        let session = SessionManager::new();
        assert!(!session.is_unlocked(&address));

        session.unlock_with_key(&address, &vault_data, &key).unwrap();
        assert!(session.is_unlocked(&address));

        session.lock(&address);
        assert!(!session.is_unlocked(&address));
    }

    #[test]
    fn test_get_signer_when_unlocked() {
        let (seed, address) = test_seed_and_address();
        let key = vault::generate_vault_key().unwrap();
        let vault_data = vault::encrypt_with_key(&seed, &key).unwrap();

        let session = SessionManager::new();
        session.unlock_with_key(&address, &vault_data, &key).unwrap();

        let signer = session.get_signer(&address).unwrap();
        assert_eq!(signer.public_key().to_base58(), address);
    }

    #[test]
    fn test_get_signer_when_locked_fails() {
        let session = SessionManager::new();
        let result = session.get_signer("SomeAddress123");
        assert!(result.is_err());
    }

    #[test]
    fn test_wrong_key_fails_unlock() {
        let (seed, address) = test_seed_and_address();
        let key = vault::generate_vault_key().unwrap();
        let wrong_key = vault::generate_vault_key().unwrap();
        let vault_data = vault::encrypt_with_key(&seed, &key).unwrap();

        let session = SessionManager::new();
        let result = session.unlock_with_key(&address, &vault_data, &wrong_key);
        assert!(result.is_err());
        assert!(!session.is_unlocked(&address));
    }

    #[test]
    fn test_lock_all() {
        let (seed1, addr1) = test_seed_and_address();
        let seed2 = [0x02u8; 32];
        let signer2 = SoftwareSigner::from_seed(&seed2).unwrap();
        let addr2 = signer2.public_key().to_base58();

        let key = vault::generate_vault_key().unwrap();
        let vault1 = vault::encrypt_with_key(&seed1, &key).unwrap();
        let vault2 = vault::encrypt_with_key(&seed2, &key).unwrap();

        let session = SessionManager::new();
        session.unlock_with_key(&addr1, &vault1, &key).unwrap();
        session.unlock_with_key(&addr2, &vault2, &key).unwrap();

        assert!(session.is_unlocked(&addr1));
        assert!(session.is_unlocked(&addr2));

        session.lock_all();
        assert!(!session.is_unlocked(&addr1));
        assert!(!session.is_unlocked(&addr2));
    }

    #[test]
    fn test_unlock_with_password() {
        let (seed, address) = test_seed_and_address();
        let password = b"test-password";
        let vault_data = vault::encrypt(&seed, password, vault::KdfStrength::Mobile).unwrap();

        let session = SessionManager::new();
        session
            .unlock_with_password(&address, &vault_data, password, vault::KdfStrength::Mobile)
            .unwrap();
        assert!(session.is_unlocked(&address));

        let signer = session.get_signer(&address).unwrap();
        assert_eq!(signer.public_key().to_base58(), address);
    }
}
