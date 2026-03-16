use std::sync::{OnceLock, RwLock};

use deadbolt_core::models::WalletManager;

use super::types::{CreateWalletResult, WalletInfoDto};

/// Platform-appropriate secure storage.
#[cfg(target_os = "macos")]
fn storage() -> deadbolt_core::storage::KeychainStorage {
    deadbolt_core::storage::KeychainStorage::new()
}

/// Public accessor for secure storage (for use by sibling modules like auth).
#[cfg(target_os = "macos")]
#[flutter_rust_bridge::frb(ignore)]
pub fn storage_pub() -> deadbolt_core::storage::KeychainStorage {
    deadbolt_core::storage::KeychainStorage::new()
}

/// Global singleton wallet manager (public for sibling modules).
#[flutter_rust_bridge::frb(ignore)]
pub fn manager_pub() -> &'static RwLock<WalletManager> {
    manager()
}

fn manager() -> &'static RwLock<WalletManager> {
    static INSTANCE: OnceLock<RwLock<WalletManager>> = OnceLock::new();
    INSTANCE.get_or_init(|| {
        let mgr = WalletManager::new().expect("Failed to initialize WalletManager");
        RwLock::new(mgr)
    })
}

/// Create a new wallet from a generated mnemonic.
pub fn create_wallet(name: String, word_count: u32) -> Result<CreateWalletResult, String> {
    let mut mgr = manager().write().map_err(|e| e.to_string())?;
    let (info, words) = mgr
        .create_wallet(&name, word_count as usize, &storage())
        .map_err(|e| e.to_string())?;
    Ok(CreateWalletResult {
        wallet: WalletInfoDto::from_core(&info),
        mnemonic_words: words,
    })
}

/// Import a wallet from a mnemonic phrase.
pub fn import_wallet(name: String, words: Vec<String>) -> Result<WalletInfoDto, String> {
    let mut mgr = manager().write().map_err(|e| e.to_string())?;
    let info = mgr
        .import_wallet(&name, &words, &storage())
        .map_err(|e| e.to_string())?;
    Ok(WalletInfoDto::from_core(&info))
}

/// List all wallets.
pub fn list_wallets() -> Result<Vec<WalletInfoDto>, String> {
    let mgr = manager().read().map_err(|e| e.to_string())?;
    Ok(mgr
        .list_wallets()
        .iter()
        .map(WalletInfoDto::from_core)
        .collect())
}

/// Set the active wallet by address.
pub fn set_active_wallet(address: String) -> Result<(), String> {
    let mut mgr = manager().write().map_err(|e| e.to_string())?;
    mgr.set_active_wallet(&address).map_err(|e| e.to_string())
}

/// Get the active wallet address.
#[flutter_rust_bridge::frb(sync)]
pub fn get_active_wallet() -> Result<Option<String>, String> {
    let mgr = manager().read().map_err(|e| e.to_string())?;
    Ok(mgr.active_wallet().map(String::from))
}

/// Remove a wallet by address.
pub fn remove_wallet(address: String) -> Result<(), String> {
    let mut mgr = manager().write().map_err(|e| e.to_string())?;
    mgr.remove_wallet(&address, &storage())
        .map_err(|e| e.to_string())
}

/// Unlock a wallet (loads seed into memory session).
pub fn unlock_wallet(address: String) -> Result<(), String> {
    let mgr = manager().read().map_err(|e| e.to_string())?;
    mgr.unlock(&address, &storage())
        .map_err(|e| e.to_string())
}

/// Lock a wallet (zeroizes seed from memory).
pub fn lock_wallet(address: String) -> Result<(), String> {
    let mgr = manager().read().map_err(|e| e.to_string())?;
    mgr.lock(&address);
    Ok(())
}

/// Lock all wallets.
pub fn lock_all_wallets() -> Result<(), String> {
    let mgr = manager().read().map_err(|e| e.to_string())?;
    mgr.lock_all();
    Ok(())
}

/// Check if a wallet is unlocked.
#[flutter_rust_bridge::frb(sync)]
pub fn is_wallet_unlocked(address: String) -> Result<bool, String> {
    let mgr = manager().read().map_err(|e| e.to_string())?;
    Ok(mgr.is_unlocked(&address))
}

/// Retrieve the mnemonic for a wallet.
pub fn get_mnemonic(address: String) -> Result<Vec<String>, String> {
    let mgr = manager().read().map_err(|e| e.to_string())?;
    mgr.get_mnemonic(&address, &storage())
        .map_err(|e| e.to_string())
}

/// Check if the user needs to go through onboarding.
#[flutter_rust_bridge::frb(sync)]
pub fn needs_onboarding() -> Result<bool, String> {
    let mgr = manager().read().map_err(|e| e.to_string())?;
    Ok(mgr.config().needs_onboarding())
}

/// Mark onboarding as completed.
pub fn complete_onboarding() -> Result<(), String> {
    let mut mgr = manager().write().map_err(|e| e.to_string())?;
    mgr.config_mut()
        .mark_onboarding_completed()
        .map_err(|e| e.to_string())
}

/// Validate a mnemonic phrase (for import flow).
#[flutter_rust_bridge::frb(sync)]
pub fn validate_mnemonic(words: Vec<String>) -> bool {
    deadbolt_core::crypto::mnemonic::validate(&words)
}

/// Pick N random BIP39 words (for quiz distractors).
#[flutter_rust_bridge::frb(sync)]
pub fn random_bip39_words(count: u32) -> Vec<String> {
    deadbolt_core::crypto::mnemonic::random_words(count as usize)
}

/// Reset onboarding flag (debug/settings use).
pub fn reset_onboarding() -> Result<(), String> {
    let mut mgr = manager().write().map_err(|e| e.to_string())?;
    let config = mgr.config_mut();
    config.onboarding_completed = false;
    config.save().map_err(|e| e.to_string())
}

/// Get the current network setting.
#[flutter_rust_bridge::frb(sync)]
pub fn get_network() -> Result<String, String> {
    let mgr = manager().read().map_err(|e| e.to_string())?;
    Ok(mgr.config().network.clone())
}

/// Set the network (e.g. "mainnet", "devnet", "testnet").
pub fn set_network(network: String) -> Result<(), String> {
    let mut mgr = manager().write().map_err(|e| e.to_string())?;
    let config = mgr.config_mut();
    config.network = network;
    config.save().map_err(|e| e.to_string())
}

/// Get the Helius API key.
#[flutter_rust_bridge::frb(sync)]
pub fn get_helius_api_key() -> Result<String, String> {
    let mgr = manager().read().map_err(|e| e.to_string())?;
    Ok(mgr.config().helius_api_key.clone())
}

/// Set the Helius API key.
pub fn set_helius_api_key(key: String) -> Result<(), String> {
    let mut mgr = manager().write().map_err(|e| e.to_string())?;
    let config = mgr.config_mut();
    config.helius_api_key = key;
    config.save().map_err(|e| e.to_string())
}
