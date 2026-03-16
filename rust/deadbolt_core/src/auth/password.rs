use security_framework::passwords::{
    delete_generic_password, get_generic_password, set_generic_password,
};
use zeroize::Zeroize;

use crate::crypto::vault::{derive_key, KdfStrength};
use crate::models::DeadboltError;

const SERVICE: &str = "com.deadbolt.wallet";
const PASSWORD_HASH_ACCOUNT: &str = "app_password_hash";

/// Set the app password. Hashes with scrypt (Desktop strength) and stores
/// the [16B salt || 32B hash] in the Keychain.
///
/// This is CPU-intensive (scrypt). Call from an async context.
pub fn set_app_password(password: &[u8]) -> Result<(), DeadboltError> {
    // Generate a 16-byte random salt
    let mut salt = [0u8; 16];
    getrandom::getrandom(&mut salt)
        .map_err(|e| DeadboltError::VaultError(format!("RNG error: {e}")))?;

    // Derive a 32-byte hash from the password and salt using scrypt Desktop strength
    let mut hash = derive_key(password, &salt, KdfStrength::Desktop)?;

    // Concatenate into a 48-byte stored value: [16B salt || 32B hash]
    let mut stored = [0u8; 48];
    stored[..16].copy_from_slice(&salt);
    stored[16..].copy_from_slice(&hash);

    // Zeroize the intermediate hash
    hash.zeroize();

    // Delete any existing entry first (update semantics)
    let _ = delete_generic_password(SERVICE, PASSWORD_HASH_ACCOUNT);

    // Store in Keychain
    set_generic_password(SERVICE, PASSWORD_HASH_ACCOUNT, &stored)
        .map_err(|e| DeadboltError::StorageError(e.to_string()))?;

    Ok(())
}

/// Verify the app password against the stored hash.
/// Returns Ok(()) on match, Err(AuthenticationFailed) on mismatch,
/// Err(StorageItemNotFound) if no password has been set.
///
/// This is CPU-intensive (scrypt). Call from an async context.
pub fn verify_app_password(password: &[u8]) -> Result<(), DeadboltError> {
    // Read stored 48-byte value from Keychain
    let stored = get_generic_password(SERVICE, PASSWORD_HASH_ACCOUNT).map_err(|e| {
        if e.to_string().contains("-25300") {
            DeadboltError::StorageItemNotFound
        } else {
            DeadboltError::StorageError(e.to_string())
        }
    })?;

    // Validate length
    if stored.len() != 48 {
        return Err(DeadboltError::VaultError("Corrupt password hash".into()));
    }

    // Split into salt and expected hash
    let salt = &stored[..16];
    let expected_hash = &stored[16..];

    // Derive actual hash from the provided password
    let mut actual_hash = derive_key(password, salt, KdfStrength::Desktop)?;

    // Constant-time comparison to prevent timing attacks
    let matches = constant_time_eq::constant_time_eq(&actual_hash, expected_hash);

    // Zeroize sensitive data
    actual_hash.zeroize();

    if matches {
        Ok(())
    } else {
        Err(DeadboltError::AuthenticationFailed("Invalid password".into()))
    }
}

/// Change the app password. Verifies the current password before setting new one.
///
/// This is CPU-intensive (scrypt x2). Call from an async context.
pub fn change_app_password(current: &[u8], new_password: &[u8]) -> Result<(), DeadboltError> {
    // Verify current password first
    verify_app_password(current)?;

    // Set new password
    set_app_password(new_password)
}

/// Check if an app password has been set (non-blocking).
pub fn has_app_password() -> bool {
    get_generic_password(SERVICE, PASSWORD_HASH_ACCOUNT).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Use a unique account name per test run to avoid Keychain conflicts between
    /// parallel test runs or stale state from prior runs.
    fn test_account() -> String {
        format!("test_app_password_{}", std::process::id())
    }

    fn cleanup_test_entry() {
        let account = test_account();
        let _ = delete_generic_password(SERVICE, &account);
    }

    /// Override the constants for testing using a helper that calls the raw functions
    /// with a test-specific account name. This avoids polluting the real Keychain entry.
    fn set_test_password(password: &[u8]) -> Result<(), DeadboltError> {
        let mut salt = [0u8; 16];
        getrandom::getrandom(&mut salt)
            .map_err(|e| DeadboltError::VaultError(format!("RNG error: {e}")))?;
        let mut hash = derive_key(password, &salt, KdfStrength::Desktop)?;
        let mut stored = [0u8; 48];
        stored[..16].copy_from_slice(&salt);
        stored[16..].copy_from_slice(&hash);
        hash.zeroize();
        let _ = delete_generic_password(SERVICE, &test_account());
        set_generic_password(SERVICE, &test_account(), &stored)
            .map_err(|e| DeadboltError::StorageError(e.to_string()))
    }

    fn verify_test_password(password: &[u8]) -> Result<(), DeadboltError> {
        let stored = get_generic_password(SERVICE, &test_account()).map_err(|e| {
            if e.to_string().contains("-25300") {
                DeadboltError::StorageItemNotFound
            } else {
                DeadboltError::StorageError(e.to_string())
            }
        })?;
        if stored.len() != 48 {
            return Err(DeadboltError::VaultError("Corrupt password hash".into()));
        }
        let salt = &stored[..16];
        let expected_hash = &stored[16..];
        let mut actual_hash = derive_key(password, salt, KdfStrength::Desktop)?;
        let matches = constant_time_eq::constant_time_eq(&actual_hash, expected_hash);
        actual_hash.zeroize();
        if matches {
            Ok(())
        } else {
            Err(DeadboltError::AuthenticationFailed("Invalid password".into()))
        }
    }

    fn has_test_password() -> bool {
        get_generic_password(SERVICE, &test_account()).is_ok()
    }

    fn change_test_password(current: &[u8], new_password: &[u8]) -> Result<(), DeadboltError> {
        verify_test_password(current)?;
        set_test_password(new_password)
    }

    #[test]
    fn test_set_password_succeeds() {
        cleanup_test_entry();
        assert!(set_test_password(b"testpass123").is_ok());
        cleanup_test_entry();
    }

    #[test]
    fn test_verify_correct_password_succeeds() {
        cleanup_test_entry();
        set_test_password(b"testpass123").unwrap();
        assert!(verify_test_password(b"testpass123").is_ok());
        cleanup_test_entry();
    }

    #[test]
    fn test_verify_wrong_password_fails() {
        cleanup_test_entry();
        set_test_password(b"testpass123").unwrap();
        let result = verify_test_password(b"wrongpass");
        assert!(result.is_err());
        cleanup_test_entry();
    }

    #[test]
    fn test_has_password_false_before_set() {
        cleanup_test_entry();
        assert!(!has_test_password());
    }

    #[test]
    fn test_has_password_true_after_set() {
        cleanup_test_entry();
        set_test_password(b"testpass123").unwrap();
        assert!(has_test_password());
        cleanup_test_entry();
    }

    #[test]
    fn test_change_password_succeeds() {
        cleanup_test_entry();
        set_test_password(b"testpass123").unwrap();
        assert!(change_test_password(b"testpass123", b"newpass456").is_ok());
        cleanup_test_entry();
    }

    #[test]
    fn test_verify_new_password_after_change() {
        cleanup_test_entry();
        set_test_password(b"testpass123").unwrap();
        change_test_password(b"testpass123", b"newpass456").unwrap();
        assert!(verify_test_password(b"newpass456").is_ok());
        cleanup_test_entry();
    }

    #[test]
    fn test_change_password_wrong_current_fails() {
        cleanup_test_entry();
        set_test_password(b"testpass123").unwrap();
        let result = change_test_password(b"wrongcurrent", b"newpass");
        assert!(result.is_err());
        cleanup_test_entry();
    }
}
