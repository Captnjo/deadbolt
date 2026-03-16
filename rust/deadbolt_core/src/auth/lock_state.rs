use std::sync::atomic::{AtomicBool, Ordering};

use crate::models::DeadboltError;

/// Global lock state. Starts locked (true) at application startup.
/// Set to false after successful password verification (unlock).
/// Set to true on lock_app or app backgrounding.
static APP_LOCKED: AtomicBool = AtomicBool::new(true);

/// Set the application lock state.
pub fn set_locked(locked: bool) {
    APP_LOCKED.store(locked, Ordering::SeqCst);
}

/// Check if the application is currently locked.
pub fn is_app_locked() -> bool {
    APP_LOCKED.load(Ordering::SeqCst)
}

/// Assert that the app is unlocked. Returns Err(WalletLocked) if locked.
/// Call this at the top of any function that requires the app to be unlocked.
pub fn assert_unlocked() -> Result<(), DeadboltError> {
    if APP_LOCKED.load(Ordering::SeqCst) {
        Err(DeadboltError::WalletLocked)
    } else {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_app_locked_starts_true() {
        // APP_LOCKED is initialized to true; in tests it may have been changed
        // by other tests, so we explicitly set and check
        set_locked(true);
        assert!(is_app_locked());
    }

    #[test]
    fn test_set_locked_false() {
        set_locked(false);
        assert!(!is_app_locked());
        // Restore
        set_locked(true);
    }

    #[test]
    fn test_assert_unlocked_when_unlocked() {
        set_locked(false);
        assert!(assert_unlocked().is_ok());
        // Restore
        set_locked(true);
    }

    #[test]
    fn test_assert_unlocked_when_locked() {
        set_locked(true);
        let result = assert_unlocked();
        assert!(result.is_err());
        match result {
            Err(DeadboltError::WalletLocked) => {}
            _ => panic!("Expected WalletLocked error"),
        }
    }
}
