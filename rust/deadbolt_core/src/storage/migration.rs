use crate::crypto::vault;
use crate::models::DeadboltError;

use super::SecureStorage;

/// Result of migrating a single wallet from legacy Keychain format.
#[derive(Debug)]
pub struct MigrationResult {
    pub address: String,
    pub had_mnemonic: bool,
}

/// Migrate a wallet from legacy Keychain format (raw seed in Keychain)
/// to vault format (encrypted file + vault key in Keychain).
///
/// Steps:
/// 1. Read raw seed from Keychain (legacy format)
/// 2. Generate a new vault encryption key
/// 3. Encrypt the seed into a vault blob
/// 4. Optionally encrypt the mnemonic into a separate vault blob
/// 5. Store the vault key in secure storage (replaces the raw seed entry)
/// 6. Delete the legacy mnemonic entry
///
/// Returns the encrypted vault data blobs (caller writes to disk).
#[cfg(target_os = "macos")]
pub fn migrate_legacy_wallet(
    address: &str,
    storage: &dyn SecureStorage,
) -> Result<(Vec<u8>, Option<Vec<u8>>, MigrationResult), DeadboltError> {
    use super::keychain;
    use zeroize::Zeroize;

    // 1. Read legacy seed
    let mut seed = keychain::read_legacy_seed(address)?;

    // 2. Generate vault key
    let vault_key = vault::generate_vault_key()?;

    // 3. Encrypt seed
    let seed_vault = vault::encrypt_with_key(&seed, &vault_key)?;

    // 4. Optionally encrypt mnemonic
    let mnemonic_vault = if let Ok(Some(words)) = keychain::read_legacy_mnemonic(address) {
        let phrase = words.join(" ");
        let vault_data = vault::encrypt_with_key(phrase.as_bytes(), &vault_key)?;
        Some(vault_data)
    } else {
        None
    };

    // 5. Store vault key (replaces the raw seed in Keychain)
    storage.store_vault_key(&vault_key, address)?;

    // 6. Delete legacy mnemonic entry (seed entry is already overwritten by vault key)
    keychain::delete_legacy_entries(address);

    // Zeroize sensitive data
    seed.zeroize();

    let result = MigrationResult {
        address: address.to_string(),
        had_mnemonic: mnemonic_vault.is_some(),
    };

    Ok((seed_vault, mnemonic_vault, result))
}

/// Check if a wallet address has a legacy (unmigrated) entry in Keychain.
#[cfg(target_os = "macos")]
pub fn needs_migration(address: &str) -> bool {
    super::keychain::has_legacy_seed(address)
}

/// Placeholder for non-macOS platforms (no legacy data to migrate).
#[cfg(not(target_os = "macos"))]
pub fn needs_migration(_address: &str) -> bool {
    false
}
