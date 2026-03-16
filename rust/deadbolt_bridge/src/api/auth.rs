use deadbolt_core::auth;

/// Set the app password (during onboarding). Async because scrypt is CPU-intensive.
pub async fn set_app_password(password: String) -> Result<(), String> {
    auth::password::set_app_password(password.as_bytes())
        .map_err(|e| e.to_string())
}

/// Verify the app password (for unlock). Async because scrypt is CPU-intensive.
pub async fn verify_app_password(password: String) -> Result<(), String> {
    auth::password::verify_app_password(password.as_bytes())
        .map_err(|e| e.to_string())
}

/// Change the app password. Requires current password verification first.
pub async fn change_app_password(current: String, new_password: String) -> Result<(), String> {
    auth::password::change_app_password(current.as_bytes(), new_password.as_bytes())
        .map_err(|e| e.to_string())
}

/// Check if an app password has been set.
#[flutter_rust_bridge::frb(sync)]
pub fn has_app_password() -> bool {
    auth::password::has_app_password()
}

/// Check if the app is currently locked.
#[flutter_rust_bridge::frb(sync)]
pub fn is_app_locked() -> bool {
    auth::lock_state::is_app_locked()
}

/// Lock the app: set AtomicBool to true, then lock all wallets (zeroize seeds).
pub async fn lock_app() -> Result<(), String> {
    auth::lock_state::set_locked(true);
    // Also lock all wallets via the existing wallet manager
    super::wallet::lock_all_wallets()
}

/// Unlock the app after password verification.
/// Caller must call verify_app_password first, then call this.
/// This unlocks all Keychain wallets into the session and sets AtomicBool to false.
pub async fn unlock_app() -> Result<(), String> {
    // Unlock all wallets from Keychain storage
    let mgr = super::wallet::manager_pub().read().map_err(|e| e.to_string())?;
    let storage = super::wallet::storage_pub();
    for wallet in mgr.list_wallets() {
        if wallet.source == deadbolt_core::WalletSource::Keychain {
            let _ = mgr.unlock(&wallet.address, &storage);
        }
    }
    // Set the global lock flag to unlocked AFTER wallets are loaded
    auth::lock_state::set_locked(false);
    Ok(())
}
