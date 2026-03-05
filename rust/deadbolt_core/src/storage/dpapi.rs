use crate::models::DeadboltError;

use super::SecureStorage;

/// Windows DPAPI storage backend.
/// Uses CryptProtectData/CryptUnprotectData to encrypt vault keys
/// under the current user's profile. Data is automatically encrypted
/// with the user's Windows login credentials.
pub struct DpapiStorage;

impl DpapiStorage {
    pub fn new() -> Self {
        Self
    }

    /// Get the vault key file path for an address.
    fn key_path(address: &str) -> std::path::PathBuf {
        let base = dirs_for_vault();
        base.join(format!("{address}.key"))
    }
}

impl SecureStorage for DpapiStorage {
    fn store_vault_key(&self, key: &[u8; 32], address: &str) -> Result<(), DeadboltError> {
        use windows::Win32::Security::Cryptography::{
            CryptProtectData, CRYPT_INTEGER_BLOB, CRYPTPROTECT_LOCAL_MACHINE,
        };
        use windows::core::PCWSTR;

        let mut data_in = CRYPT_INTEGER_BLOB {
            cbData: key.len() as u32,
            pbData: key.as_ptr() as *mut u8,
        };

        let mut data_out = CRYPT_INTEGER_BLOB::default();

        unsafe {
            CryptProtectData(
                &mut data_in,
                PCWSTR::null(),
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                0,
                &mut data_out,
            )
            .map_err(|e| DeadboltError::StorageError(format!("DPAPI encrypt failed: {e}")))?;

            let encrypted =
                std::slice::from_raw_parts(data_out.pbData, data_out.cbData as usize).to_vec();

            // Free the DPAPI-allocated buffer
            windows::Win32::System::Memory::LocalFree(
                windows::Win32::Foundation::HLOCAL(data_out.pbData as _),
            );

            // Write encrypted data to file
            let path = Self::key_path(address);
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent)
                    .map_err(|e| DeadboltError::StorageError(format!("mkdir failed: {e}")))?;
            }
            std::fs::write(&path, &encrypted)
                .map_err(|e| DeadboltError::StorageError(format!("write failed: {e}")))?;
        }

        Ok(())
    }

    fn retrieve_vault_key(&self, address: &str) -> Result<[u8; 32], DeadboltError> {
        use windows::Win32::Security::Cryptography::{CryptUnprotectData, CRYPT_INTEGER_BLOB};

        let path = Self::key_path(address);
        let encrypted = std::fs::read(&path).map_err(|e| {
            if e.kind() == std::io::ErrorKind::NotFound {
                DeadboltError::StorageItemNotFound
            } else {
                DeadboltError::StorageError(format!("read failed: {e}"))
            }
        })?;

        let mut data_in = CRYPT_INTEGER_BLOB {
            cbData: encrypted.len() as u32,
            pbData: encrypted.as_ptr() as *mut u8,
        };

        let mut data_out = CRYPT_INTEGER_BLOB::default();

        unsafe {
            CryptUnprotectData(
                &mut data_in,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                0,
                &mut data_out,
            )
            .map_err(|e| DeadboltError::StorageError(format!("DPAPI decrypt failed: {e}")))?;

            let decrypted =
                std::slice::from_raw_parts(data_out.pbData, data_out.cbData as usize);

            if decrypted.len() != 32 {
                windows::Win32::System::Memory::LocalFree(
                    windows::Win32::Foundation::HLOCAL(data_out.pbData as _),
                );
                return Err(DeadboltError::StorageError(format!(
                    "Vault key has unexpected length: {}",
                    decrypted.len()
                )));
            }

            let mut key = [0u8; 32];
            key.copy_from_slice(decrypted);

            windows::Win32::System::Memory::LocalFree(
                windows::Win32::Foundation::HLOCAL(data_out.pbData as _),
            );

            Ok(key)
        }
    }

    fn delete_vault_key(&self, address: &str) -> Result<(), DeadboltError> {
        let path = Self::key_path(address);
        let _ = std::fs::remove_file(path);
        Ok(())
    }

    fn list_addresses(&self) -> Result<Vec<String>, DeadboltError> {
        // Addresses tracked in config.json, not enumerated from DPAPI files
        Ok(Vec::new())
    }
}

/// Get the vault keys directory path.
fn dirs_for_vault() -> std::path::PathBuf {
    // Use %APPDATA%/deadbolt/vault_keys/ on Windows
    let appdata = std::env::var("APPDATA").unwrap_or_else(|_| {
        let home = std::env::var("USERPROFILE").unwrap_or_else(|_| ".".to_string());
        format!("{home}/AppData/Roaming")
    });
    std::path::PathBuf::from(appdata)
        .join("deadbolt")
        .join("vault_keys")
}
