use crate::models::DeadboltError;

/// Trait for platform-specific secure storage backends.
/// Stores vault encryption keys (not raw seeds) in platform secure storage.
pub trait SecureStorage: Send + Sync {
    /// Store a 32-byte vault encryption key, keyed by Base58 wallet address.
    fn store_vault_key(&self, key: &[u8; 32], address: &str) -> Result<(), DeadboltError>;

    /// Retrieve a vault encryption key by Base58 wallet address.
    fn retrieve_vault_key(&self, address: &str) -> Result<[u8; 32], DeadboltError>;

    /// Delete a vault encryption key by address.
    fn delete_vault_key(&self, address: &str) -> Result<(), DeadboltError>;

    /// List all stored wallet addresses.
    fn list_addresses(&self) -> Result<Vec<String>, DeadboltError>;
}

// macOS / iOS Keychain
#[cfg(any(target_os = "macos", target_os = "ios"))]
mod keychain;

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub use keychain::KeychainStorage;

// Windows DPAPI
#[cfg(target_os = "windows")]
mod dpapi;

#[cfg(target_os = "windows")]
pub use dpapi::DpapiStorage;

// Linux Secret Service (GNOME Keyring / KDE Wallet)
#[cfg(target_os = "linux")]
mod secret_service;

#[cfg(target_os = "linux")]
pub use secret_service::SecretServiceStorage;

pub mod migration;
pub mod session;
pub use session::SessionManager;

#[cfg(test)]
pub mod memory;

#[cfg(test)]
pub use memory::MemoryStorage;
