use std::path::PathBuf;

use zeroize::Zeroize;

use crate::crypto::mnemonic;
use crate::crypto::signer::SoftwareSigner;
use crate::crypto::vault;
use crate::models::config::AppConfig;
use crate::models::wallet::{WalletInfo, WalletSource};
use crate::models::DeadboltError;
use crate::storage::SecureStorage;
use crate::storage::SessionManager;

/// Manages wallet lifecycle: create, import, list, delete, lock/unlock.
pub struct WalletManager {
    config: AppConfig,
    session: SessionManager,
}

impl WalletManager {
    /// Create a new WalletManager, loading config from disk.
    pub fn new() -> Result<Self, DeadboltError> {
        let config = AppConfig::load()?;
        Ok(Self {
            config,
            session: SessionManager::new(),
        })
    }

    /// Create with an explicit config (for testing).
    pub fn with_config(config: AppConfig) -> Self {
        Self {
            config,
            session: SessionManager::new(),
        }
    }

    /// Create a new wallet from a generated mnemonic.
    /// Returns the wallet info and mnemonic words (for backup display).
    pub fn create_wallet(
        &mut self,
        name: &str,
        word_count: usize,
        storage: &dyn SecureStorage,
    ) -> Result<(WalletInfo, Vec<String>), DeadboltError> {
        // Generate mnemonic
        let words = mnemonic::generate(word_count)?;

        // Derive keypair
        let (pubkey, mut seed) = mnemonic::derive_keypair(&words, "")?;
        let address = pubkey.to_base58();

        // Generate vault key and encrypt seed
        let mut vault_key = vault::generate_vault_key()?;
        let seed_vault = vault::encrypt_with_key(&seed, &vault_key)?;

        // Encrypt mnemonic
        let mut phrase = words.join(" ");
        let mnemonic_vault = vault::encrypt_with_key(phrase.as_bytes(), &vault_key)?;

        // Write vault files
        Self::write_vault_file(&address, "vault", &seed_vault)?;
        Self::write_vault_file(&address, "mnemonic.vault", &mnemonic_vault)?;

        // Store vault key in platform secure storage
        storage.store_vault_key(&vault_key, &address)?;

        // Zeroize sensitive data
        seed.zeroize();
        vault_key.zeroize();
        phrase.zeroize();

        // Add to config
        let wallet = WalletInfo {
            address: address.clone(),
            name: name.to_string(),
            source: WalletSource::Keychain,
        };
        self.config.wallets.push(wallet.clone());
        if self.config.active_wallet.is_none() {
            self.config.active_wallet = Some(address);
        }
        self.config.save()?;

        Ok((wallet, words))
    }

    /// Import a wallet from a mnemonic phrase.
    pub fn import_wallet(
        &mut self,
        name: &str,
        words: &[String],
        storage: &dyn SecureStorage,
    ) -> Result<WalletInfo, DeadboltError> {
        // Validate mnemonic
        if !mnemonic::validate(words) {
            return Err(DeadboltError::InvalidMnemonic(
                "Invalid mnemonic phrase".into(),
            ));
        }

        // Derive keypair
        let (pubkey, mut seed) = mnemonic::derive_keypair(words, "")?;
        let address = pubkey.to_base58();

        // Check for duplicate
        if self.config.wallets.iter().any(|w| w.address == address) {
            seed.zeroize();
            return Err(DeadboltError::StorageError(format!(
                "Wallet already exists: {address}"
            )));
        }

        // Generate vault key and encrypt seed
        let mut vault_key = vault::generate_vault_key()?;
        let seed_vault = vault::encrypt_with_key(&seed, &vault_key)?;

        // Encrypt mnemonic
        let mut phrase = words.join(" ");
        let mnemonic_vault = vault::encrypt_with_key(phrase.as_bytes(), &vault_key)?;

        // Write vault files
        Self::write_vault_file(&address, "vault", &seed_vault)?;
        Self::write_vault_file(&address, "mnemonic.vault", &mnemonic_vault)?;

        // Store vault key in platform secure storage
        storage.store_vault_key(&vault_key, &address)?;

        // Zeroize sensitive data
        seed.zeroize();
        vault_key.zeroize();
        phrase.zeroize();

        // Add to config
        let wallet = WalletInfo {
            address: address.clone(),
            name: name.to_string(),
            source: WalletSource::Keychain,
        };
        self.config.wallets.push(wallet.clone());
        if self.config.active_wallet.is_none() {
            self.config.active_wallet = Some(address);
        }
        self.config.save()?;

        Ok(wallet)
    }

    /// List all wallets.
    pub fn list_wallets(&self) -> &[WalletInfo] {
        &self.config.wallets
    }

    /// Get the active wallet address.
    pub fn active_wallet(&self) -> Option<&str> {
        self.config.active_wallet.as_deref()
    }

    /// Set the active wallet.
    pub fn set_active_wallet(&mut self, address: &str) -> Result<(), DeadboltError> {
        if !self.config.wallets.iter().any(|w| w.address == address) {
            return Err(DeadboltError::NoWalletLoaded);
        }
        self.config.active_wallet = Some(address.to_string());
        self.config.save()
    }

    /// Remove a wallet and its vault files.
    pub fn remove_wallet(
        &mut self,
        address: &str,
        storage: &dyn SecureStorage,
    ) -> Result<(), DeadboltError> {
        // Lock if unlocked
        self.session.lock(address);

        // Remove vault files
        let _ = std::fs::remove_file(Self::vault_path(address, "vault"));
        let _ = std::fs::remove_file(Self::vault_path(address, "mnemonic.vault"));

        // Remove vault key from secure storage
        storage.delete_vault_key(address)?;

        // Remove from config
        self.config.wallets.retain(|w| w.address != address);
        if self.config.active_wallet.as_deref() == Some(address) {
            self.config.active_wallet = self.config.wallets.first().map(|w| w.address.clone());
        }
        self.config.save()
    }

    /// Unlock a wallet using its vault key from platform secure storage.
    pub fn unlock(&self, address: &str, storage: &dyn SecureStorage) -> Result<(), DeadboltError> {
        let vault_key = storage.retrieve_vault_key(address)?;
        let vault_data = Self::read_vault_file(address, "vault")?;
        self.session.unlock_with_key(address, &vault_data, &vault_key)
    }

    /// Lock a wallet, zeroizing its seed from memory.
    pub fn lock(&self, address: &str) {
        self.session.lock(address);
    }

    /// Lock all wallets.
    pub fn lock_all(&self) {
        self.session.lock_all();
    }

    /// Check if a wallet is unlocked.
    pub fn is_unlocked(&self, address: &str) -> bool {
        self.session.is_unlocked(address)
    }

    /// Get a signer for the active unlocked wallet.
    pub fn get_active_signer(&self) -> Result<SoftwareSigner, DeadboltError> {
        let address = self
            .config
            .active_wallet
            .as_deref()
            .ok_or(DeadboltError::NoWalletLoaded)?;
        self.session.get_signer(address)
    }

    /// Get a signer for a specific unlocked wallet.
    pub fn get_signer(&self, address: &str) -> Result<SoftwareSigner, DeadboltError> {
        self.session.get_signer(address)
    }

    /// Retrieve the mnemonic for a wallet (requires unlocked vault key).
    pub fn get_mnemonic(
        &self,
        address: &str,
        storage: &dyn SecureStorage,
    ) -> Result<Vec<String>, DeadboltError> {
        let vault_key = storage.retrieve_vault_key(address)?;
        let vault_data = Self::read_vault_file(address, "mnemonic.vault")?;
        let plaintext = vault::decrypt_with_key(&vault_data, &vault_key)?;
        // plaintext is Zeroizing<Vec<u8>>; to_vec() copies the bytes into a new Vec<u8>
        // that String::from_utf8 can consume. The Zeroizing wrapper is dropped right after,
        // zeroing the decrypted bytes from memory.
        let phrase = String::from_utf8(plaintext.to_vec())
            .map_err(|e| DeadboltError::VaultError(format!("Invalid mnemonic data: {e}")))?;
        Ok(phrase.split_whitespace().map(String::from).collect())
    }

    /// Get a reference to the current config.
    pub fn config(&self) -> &AppConfig {
        &self.config
    }

    /// Get a mutable reference to the current config.
    pub fn config_mut(&mut self) -> &mut AppConfig {
        &mut self.config
    }

    /// Register a hardware wallet (from onboarding device detection).
    pub fn register_hardware_wallet(
        &mut self,
        name: &str,
        address: &str,
    ) -> Result<WalletInfo, DeadboltError> {
        // Check for duplicate
        if self.config.wallets.iter().any(|w| w.address == address) {
            return Err(DeadboltError::StorageError(format!(
                "Wallet already exists: {address}"
            )));
        }

        let wallet = WalletInfo {
            address: address.to_string(),
            name: name.to_string(),
            source: WalletSource::Hardware,
        };
        self.config.wallets.push(wallet.clone());
        if self.config.active_wallet.is_none() {
            self.config.active_wallet = Some(address.to_string());
        }
        self.config.save()?;
        Ok(wallet)
    }

    // --- File I/O helpers ---

    fn vault_path(address: &str, suffix: &str) -> PathBuf {
        AppConfig::vault_dir().join(format!("{address}.{suffix}"))
    }

    fn write_vault_file(address: &str, suffix: &str, data: &[u8]) -> Result<(), DeadboltError> {
        let path = Self::vault_path(address, suffix);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| DeadboltError::StorageError(format!("mkdir failed: {e}")))?;
        }
        std::fs::write(&path, data)
            .map_err(|e| DeadboltError::StorageError(format!("write vault file failed: {e}")))?;

        // Restrict vault file permissions to owner-only (Unix)
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let perms = std::fs::Permissions::from_mode(0o600);
            std::fs::set_permissions(&path, perms)
                .map_err(|e| DeadboltError::StorageError(format!("chmod failed: {e}")))?;
        }

        Ok(())
    }

    fn read_vault_file(address: &str, suffix: &str) -> Result<Vec<u8>, DeadboltError> {
        let path = Self::vault_path(address, suffix);
        std::fs::read(&path).map_err(|e| {
            if e.kind() == std::io::ErrorKind::NotFound {
                DeadboltError::StorageItemNotFound
            } else {
                DeadboltError::StorageError(format!("read vault file failed: {e}"))
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::signer::TransactionSigner;
    use crate::storage::MemoryStorage;
    use std::env;

    /// Set up a temp directory for vault files during tests.
    fn with_temp_home<F: FnOnce()>(f: F) {
        let tmp = env::temp_dir().join(format!("deadbolt_test_{}", std::process::id()));
        let _ = std::fs::create_dir_all(&tmp);

        // Override HOME so AppConfig::base_dir() uses our temp dir
        let old_home = env::var("HOME").ok();
        env::set_var("HOME", &tmp);

        f();

        // Restore HOME
        if let Some(h) = old_home {
            env::set_var("HOME", h);
        }
        // Clean up
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_create_wallet() {
        with_temp_home(|| {
            let storage = MemoryStorage::new();
            let mut mgr = WalletManager::with_config(AppConfig::default());

            let (wallet, words) = mgr.create_wallet("Test", 12, &storage).unwrap();

            assert_eq!(wallet.name, "Test");
            assert_eq!(words.len(), 12);
            assert_eq!(mgr.list_wallets().len(), 1);
            assert_eq!(mgr.active_wallet(), Some(wallet.address.as_str()));
        });
    }

    #[test]
    fn test_import_wallet() {
        with_temp_home(|| {
            let storage = MemoryStorage::new();
            let mut mgr = WalletManager::with_config(AppConfig::default());

            let words: Vec<String> = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
                .split_whitespace()
                .map(String::from)
                .collect();

            let wallet = mgr.import_wallet("Imported", &words, &storage).unwrap();
            assert_eq!(wallet.name, "Imported");
            assert_eq!(wallet.address, "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk");
            assert_eq!(mgr.list_wallets().len(), 1);
        });
    }

    #[test]
    fn test_import_duplicate_rejected() {
        with_temp_home(|| {
            let storage = MemoryStorage::new();
            let mut mgr = WalletManager::with_config(AppConfig::default());

            let words: Vec<String> = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
                .split_whitespace()
                .map(String::from)
                .collect();

            mgr.import_wallet("First", &words, &storage).unwrap();
            let result = mgr.import_wallet("Second", &words, &storage);
            assert!(result.is_err());
        });
    }

    #[test]
    fn test_unlock_lock_sign() {
        with_temp_home(|| {
            let storage = MemoryStorage::new();
            let mut mgr = WalletManager::with_config(AppConfig::default());

            let (wallet, _) = mgr.create_wallet("Test", 12, &storage).unwrap();
            let addr = &wallet.address;

            assert!(!mgr.is_unlocked(addr));

            mgr.unlock(addr, &storage).unwrap();
            assert!(mgr.is_unlocked(addr));

            // Can get signer when unlocked
            let signer = mgr.get_signer(addr).unwrap();
            let sig = signer.sign(b"test message").unwrap();
            assert_eq!(sig.len(), 64);

            mgr.lock(addr);
            assert!(!mgr.is_unlocked(addr));

            // Can't get signer when locked
            assert!(mgr.get_signer(addr).is_err());
        });
    }

    #[test]
    fn test_get_mnemonic() {
        with_temp_home(|| {
            let storage = MemoryStorage::new();
            let mut mgr = WalletManager::with_config(AppConfig::default());

            let words: Vec<String> = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
                .split_whitespace()
                .map(String::from)
                .collect();

            let wallet = mgr.import_wallet("Test", &words, &storage).unwrap();
            let recovered = mgr.get_mnemonic(&wallet.address, &storage).unwrap();
            assert_eq!(recovered, words);
        });
    }

    #[test]
    fn test_remove_wallet() {
        with_temp_home(|| {
            let storage = MemoryStorage::new();
            let mut mgr = WalletManager::with_config(AppConfig::default());

            let (w1, _) = mgr.create_wallet("Wallet 1", 12, &storage).unwrap();
            let (w2, _) = mgr.create_wallet("Wallet 2", 12, &storage).unwrap();

            assert_eq!(mgr.list_wallets().len(), 2);

            mgr.remove_wallet(&w1.address, &storage).unwrap();
            assert_eq!(mgr.list_wallets().len(), 1);
            assert_eq!(mgr.active_wallet(), Some(w2.address.as_str()));
        });
    }

    #[test]
    fn test_set_active_wallet() {
        with_temp_home(|| {
            let storage = MemoryStorage::new();
            let mut mgr = WalletManager::with_config(AppConfig::default());

            let (w1, _) = mgr.create_wallet("W1", 12, &storage).unwrap();
            let (w2, _) = mgr.create_wallet("W2", 12, &storage).unwrap();

            assert_eq!(mgr.active_wallet(), Some(w1.address.as_str()));

            mgr.set_active_wallet(&w2.address).unwrap();
            assert_eq!(mgr.active_wallet(), Some(w2.address.as_str()));
        });
    }

    #[test]
    fn test_invalid_mnemonic_rejected() {
        with_temp_home(|| {
            let storage = MemoryStorage::new();
            let mut mgr = WalletManager::with_config(AppConfig::default());

            let words: Vec<String> = vec!["invalid"; 12].iter().map(|s| s.to_string()).collect();
            let result = mgr.import_wallet("Bad", &words, &storage);
            assert!(result.is_err());
        });
    }
}
