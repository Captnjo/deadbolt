use chacha20poly1305::aead::{Aead, KeyInit};
use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce};
use scrypt::Params as ScryptParams;
use zeroize::{Zeroize, Zeroizing};

use crate::models::DeadboltError;

/// Current vault file format version.
const VAULT_VERSION: u8 = 1;

/// Vault file layout:
/// [1B version][16B salt][12B nonce][N bytes ciphertext+tag]
///
/// For a 32-byte seed: total = 1 + 16 + 12 + (32 + 16) = 77 bytes
/// For a mnemonic: variable length ciphertext

/// Scrypt parameters for key derivation.
/// Mobile: log_n=15 (32768), r=8, p=1  (~100ms on modern phone)
/// Desktop: log_n=17 (131072), r=8, p=1 (~400ms on modern desktop)
#[derive(Debug, Clone, Copy)]
pub enum KdfStrength {
    Mobile,
    Desktop,
}

impl KdfStrength {
    fn scrypt_params(self) -> ScryptParams {
        match self {
            KdfStrength::Mobile => ScryptParams::new(15, 8, 1, 32).expect("valid scrypt params"),
            KdfStrength::Desktop => ScryptParams::new(17, 8, 1, 32).expect("valid scrypt params"),
        }
    }
}

/// Derive a 32-byte encryption key from a password and salt using scrypt.
pub fn derive_key(
    password: &[u8],
    salt: &[u8],
    strength: KdfStrength,
) -> Result<[u8; 32], DeadboltError> {
    let params = strength.scrypt_params();
    let mut key = [0u8; 32];
    scrypt::scrypt(password, salt, &params, &mut key)
        .map_err(|e| DeadboltError::VaultError(format!("scrypt failed: {e}")))?;
    Ok(key)
}

/// Encrypt plaintext with a 32-byte key. Returns vault file bytes.
pub fn encrypt(plaintext: &[u8], password: &[u8], strength: KdfStrength) -> Result<Vec<u8>, DeadboltError> {
    // Generate random salt and nonce
    let mut salt = [0u8; 16];
    getrandom::getrandom(&mut salt)
        .map_err(|e| DeadboltError::VaultError(format!("RNG error: {e}")))?;

    let mut nonce_bytes = [0u8; 12];
    getrandom::getrandom(&mut nonce_bytes)
        .map_err(|e| DeadboltError::VaultError(format!("RNG error: {e}")))?;

    // Derive encryption key from password
    let mut key = derive_key(password, &salt, strength)?;

    // Encrypt
    let cipher = ChaCha20Poly1305::new(Key::from_slice(&key));
    let nonce = Nonce::from_slice(&nonce_bytes);
    let ciphertext = cipher
        .encrypt(nonce, plaintext)
        .map_err(|e| DeadboltError::VaultError(format!("Encryption failed: {e}")))?;

    // Zeroize key material
    key.zeroize();

    // Build vault file: version + salt + nonce + ciphertext
    let mut vault = Vec::with_capacity(1 + 16 + 12 + ciphertext.len());
    vault.push(VAULT_VERSION);
    vault.extend_from_slice(&salt);
    vault.extend_from_slice(&nonce_bytes);
    vault.extend_from_slice(&ciphertext);

    Ok(vault)
}

/// Decrypt vault file bytes with a password. Returns plaintext wrapped in Zeroizing
/// so that the plaintext bytes are zeroed from memory when the value is dropped.
pub fn decrypt(vault_data: &[u8], password: &[u8], strength: KdfStrength) -> Result<Zeroizing<Vec<u8>>, DeadboltError> {
    // Minimum size: 1 (version) + 16 (salt) + 12 (nonce) + 16 (tag) = 45
    if vault_data.len() < 45 {
        return Err(DeadboltError::VaultError("Vault data too short".into()));
    }

    let version = vault_data[0];
    if version != VAULT_VERSION {
        return Err(DeadboltError::VaultError(format!(
            "Unsupported vault version: {version}"
        )));
    }

    let salt = &vault_data[1..17];
    let nonce_bytes = &vault_data[17..29];
    let ciphertext = &vault_data[29..];

    // Derive key from password
    let mut key = derive_key(password, salt, strength)?;

    // Decrypt
    let cipher = ChaCha20Poly1305::new(Key::from_slice(&key));
    let nonce = Nonce::from_slice(nonce_bytes);
    let plaintext = cipher
        .decrypt(nonce, ciphertext)
        .map_err(|_| DeadboltError::VaultError("Decryption failed (wrong password or corrupted data)".into()))?;

    // Zeroize key material
    key.zeroize();

    Ok(Zeroizing::new(plaintext))
}

/// Encrypt a 32-byte seed directly with a vault key (no password derivation).
/// Used for the Android hybrid flow where the vault key comes from platform secure storage.
pub fn encrypt_with_key(plaintext: &[u8], key: &[u8; 32]) -> Result<Vec<u8>, DeadboltError> {
    let mut nonce_bytes = [0u8; 12];
    getrandom::getrandom(&mut nonce_bytes)
        .map_err(|e| DeadboltError::VaultError(format!("RNG error: {e}")))?;

    let cipher = ChaCha20Poly1305::new(Key::from_slice(key));
    let nonce = Nonce::from_slice(&nonce_bytes);
    let ciphertext = cipher
        .encrypt(nonce, plaintext)
        .map_err(|e| DeadboltError::VaultError(format!("Encryption failed: {e}")))?;

    // Build vault file: version + 16 zero bytes (no salt needed) + nonce + ciphertext
    let mut vault = Vec::with_capacity(1 + 16 + 12 + ciphertext.len());
    vault.push(VAULT_VERSION);
    vault.extend_from_slice(&[0u8; 16]); // salt slot unused for direct key
    vault.extend_from_slice(&nonce_bytes);
    vault.extend_from_slice(&ciphertext);

    Ok(vault)
}

/// Decrypt vault file bytes with a vault key (no password derivation).
/// Used for the Android hybrid flow.
/// Returns plaintext wrapped in Zeroizing so that the plaintext bytes are zeroed
/// from memory when the value is dropped.
pub fn decrypt_with_key(vault_data: &[u8], key: &[u8; 32]) -> Result<Zeroizing<Vec<u8>>, DeadboltError> {
    if vault_data.len() < 45 {
        return Err(DeadboltError::VaultError("Vault data too short".into()));
    }

    let version = vault_data[0];
    if version != VAULT_VERSION {
        return Err(DeadboltError::VaultError(format!(
            "Unsupported vault version: {version}"
        )));
    }

    // Skip salt (bytes 1..17), read nonce and ciphertext
    let nonce_bytes = &vault_data[17..29];
    let ciphertext = &vault_data[29..];

    let cipher = ChaCha20Poly1305::new(Key::from_slice(key));
    let nonce = Nonce::from_slice(nonce_bytes);
    let plaintext = cipher
        .decrypt(nonce, ciphertext)
        .map_err(|_| DeadboltError::VaultError("Decryption failed (wrong key or corrupted data)".into()))?;

    Ok(Zeroizing::new(plaintext))
}

/// Generate a random 32-byte vault key for the Android hybrid flow.
pub fn generate_vault_key() -> Result<[u8; 32], DeadboltError> {
    let mut key = [0u8; 32];
    getrandom::getrandom(&mut key)
        .map_err(|e| DeadboltError::VaultError(format!("RNG error: {e}")))?;
    Ok(key)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encrypt_decrypt_roundtrip_seed() {
        let seed = [0xABu8; 32];
        let password = b"test-password-123";

        let vault_data = encrypt(&seed, password, KdfStrength::Mobile).unwrap();
        let decrypted = decrypt(&vault_data, password, KdfStrength::Mobile).unwrap();

        assert_eq!(decrypted.as_slice(), &seed);
    }

    #[test]
    fn test_encrypt_decrypt_roundtrip_mnemonic() {
        let mnemonic = b"abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let password = b"mnemonic-password";

        let vault_data = encrypt(mnemonic, password, KdfStrength::Mobile).unwrap();
        let decrypted = decrypt(&vault_data, password, KdfStrength::Mobile).unwrap();

        assert_eq!(decrypted.as_slice(), mnemonic.as_slice());
    }

    #[test]
    fn test_wrong_password_fails() {
        let seed = [0xCDu8; 32];
        let vault_data = encrypt(&seed, b"correct", KdfStrength::Mobile).unwrap();
        let result = decrypt(&vault_data, b"wrong", KdfStrength::Mobile);
        assert!(result.is_err());
    }

    #[test]
    fn test_corrupted_data_fails() {
        let seed = [0xEFu8; 32];
        let mut vault_data = encrypt(&seed, b"password", KdfStrength::Mobile).unwrap();

        // Corrupt a byte in the ciphertext
        let last = vault_data.len() - 1;
        vault_data[last] ^= 0xFF;

        let result = decrypt(&vault_data, b"password", KdfStrength::Mobile);
        assert!(result.is_err());
    }

    #[test]
    fn test_truncated_data_fails() {
        let result = decrypt(&[0u8; 10], b"password", KdfStrength::Mobile);
        assert!(result.is_err());
    }

    #[test]
    fn test_wrong_version_fails() {
        let seed = [0x11u8; 32];
        let mut vault_data = encrypt(&seed, b"password", KdfStrength::Mobile).unwrap();
        vault_data[0] = 99; // invalid version
        let result = decrypt(&vault_data, b"password", KdfStrength::Mobile);
        assert!(result.is_err());
    }

    #[test]
    fn test_different_encryptions_produce_different_output() {
        let seed = [0x42u8; 32];
        let password = b"same-password";

        let vault1 = encrypt(&seed, password, KdfStrength::Mobile).unwrap();
        let vault2 = encrypt(&seed, password, KdfStrength::Mobile).unwrap();

        // Different random salt and nonce means different ciphertext
        assert_ne!(vault1, vault2);

        // But both decrypt to the same seed
        let dec1 = decrypt(&vault1, password, KdfStrength::Mobile).unwrap();
        let dec2 = decrypt(&vault2, password, KdfStrength::Mobile).unwrap();
        assert_eq!(dec1, dec2);
    }

    #[test]
    fn test_vault_file_format() {
        let seed = [0x55u8; 32];
        let vault_data = encrypt(&seed, b"pw", KdfStrength::Mobile).unwrap();

        assert_eq!(vault_data[0], VAULT_VERSION);
        // 1 (version) + 16 (salt) + 12 (nonce) + 32 (plaintext) + 16 (tag) = 77
        assert_eq!(vault_data.len(), 77);
    }

    #[test]
    fn test_encrypt_decrypt_with_key() {
        let seed = [0xBBu8; 32];
        let key = generate_vault_key().unwrap();

        let vault_data = encrypt_with_key(&seed, &key).unwrap();
        let decrypted = decrypt_with_key(&vault_data, &key).unwrap();

        assert_eq!(decrypted.as_slice(), &seed);
    }

    #[test]
    fn test_wrong_key_fails() {
        let seed = [0xCCu8; 32];
        let key1 = generate_vault_key().unwrap();
        let key2 = generate_vault_key().unwrap();

        let vault_data = encrypt_with_key(&seed, &key1).unwrap();
        let result = decrypt_with_key(&vault_data, &key2);
        assert!(result.is_err());
    }

    #[test]
    fn test_derive_key_deterministic() {
        let password = b"test-password";
        let salt = [0xAAu8; 16];

        let key1 = derive_key(password, &salt, KdfStrength::Mobile).unwrap();
        let key2 = derive_key(password, &salt, KdfStrength::Mobile).unwrap();
        assert_eq!(key1, key2);
    }

    #[test]
    fn test_derive_key_different_passwords() {
        let salt = [0xBBu8; 16];
        let key1 = derive_key(b"password1", &salt, KdfStrength::Mobile).unwrap();
        let key2 = derive_key(b"password2", &salt, KdfStrength::Mobile).unwrap();
        assert_ne!(key1, key2);
    }

    #[test]
    fn test_derive_key_different_salts() {
        let password = b"same-password";
        let key1 = derive_key(password, &[0xAA; 16], KdfStrength::Mobile).unwrap();
        let key2 = derive_key(password, &[0xBB; 16], KdfStrength::Mobile).unwrap();
        assert_ne!(key1, key2);
    }
}
