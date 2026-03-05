use bip39::{Language, Mnemonic as Bip39Mnemonic};
use hmac::{Hmac, Mac};
use sha2::Sha512;
use zeroize::Zeroize;

use super::pubkey::SolanaPublicKey;
use crate::models::DeadboltError;

type HmacSha512 = Hmac<Sha512>;

/// Generate a new 12 or 24-word BIP39 mnemonic.
pub fn generate(word_count: usize) -> Result<Vec<String>, DeadboltError> {
    let entropy_bytes = match word_count {
        12 => 16, // 128 bits
        24 => 32, // 256 bits
        _ => {
            return Err(DeadboltError::InvalidMnemonic(format!(
                "Word count must be 12 or 24, got {word_count}"
            )));
        }
    };

    let mut entropy = vec![0u8; entropy_bytes];
    getrandom::getrandom(&mut entropy)
        .map_err(|e| DeadboltError::InvalidMnemonic(format!("RNG error: {e}")))?;

    let mnemonic = Bip39Mnemonic::from_entropy(&entropy)
        .map_err(|e| DeadboltError::InvalidMnemonic(e.to_string()))?;

    entropy.zeroize();

    Ok(mnemonic.words().map(String::from).collect())
}

/// Validate a mnemonic phrase.
pub fn validate(words: &[String]) -> bool {
    let phrase = words.join(" ");
    Bip39Mnemonic::parse(&phrase).is_ok()
}

/// Derive a 64-byte BIP39 seed from mnemonic words using PBKDF2-HMAC-SHA512.
pub fn to_seed(words: &[String], passphrase: &str) -> Result<[u8; 64], DeadboltError> {
    let phrase = words.join(" ");
    let mnemonic = Bip39Mnemonic::parse(&phrase)
        .map_err(|e| DeadboltError::InvalidMnemonic(e.to_string()))?;
    let seed = mnemonic.to_seed(passphrase);
    Ok(seed)
}

/// Derive an Ed25519 keypair from BIP39 seed using SLIP-0010 with
/// Solana derivation path m/44'/501'/0'/0'.
pub fn derive_keypair(
    words: &[String],
    passphrase: &str,
) -> Result<(SolanaPublicKey, [u8; 32]), DeadboltError> {
    let mut bip39_seed = to_seed(words, passphrase)?;

    // SLIP-0010 master key derivation
    let mut mac =
        HmacSha512::new_from_slice(b"ed25519 seed").expect("HMAC accepts any key length");
    mac.update(&bip39_seed);
    let master = mac.finalize().into_bytes();
    bip39_seed.zeroize();

    let mut key: [u8; 32] = master[..32].try_into().unwrap();
    let mut chain_code: [u8; 32] = master[32..].try_into().unwrap();

    // Derive through path m/44'/501'/0'/0'
    let path = [44u32, 501, 0, 0];
    for component in path {
        let hardened_index = component + 0x80000000;

        // Build data: 0x00 + key (32 bytes) + index (4 bytes big-endian)
        let mut data = Vec::with_capacity(37);
        data.push(0x00);
        data.extend_from_slice(&key);
        data.extend_from_slice(&hardened_index.to_be_bytes());

        let mut mac =
            HmacSha512::new_from_slice(&chain_code).expect("HMAC accepts any key length");
        mac.update(&data);
        data.zeroize();
        let derived = mac.finalize().into_bytes();

        key.copy_from_slice(&derived[..32]);
        chain_code.copy_from_slice(&derived[32..]);
    }

    // Zeroize chain code — no longer needed
    chain_code.zeroize();

    // key is the Ed25519 private key seed
    let signing_key = ed25519_dalek::SigningKey::from_bytes(&key);
    let verifying_key = signing_key.verifying_key();
    let pubkey = SolanaPublicKey::from_bytes(verifying_key.as_bytes())?;

    Ok((pubkey, key))
}

/// Pick N random words from the BIP39 English wordlist (for quiz distractors).
pub fn random_words(count: usize) -> Vec<String> {
    let wordlist = Language::English.word_list();
    let mut result = Vec::with_capacity(count);
    let mut buf = [0u8; 2];
    for _ in 0..count {
        getrandom::getrandom(&mut buf).expect("RNG failed");
        let index = u16::from_le_bytes(buf) as usize % wordlist.len();
        result.push(wordlist[index].to_string());
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_12_words() {
        let words = generate(12).unwrap();
        assert_eq!(words.len(), 12);
        assert!(validate(&words));
    }

    #[test]
    fn test_generate_24_words() {
        let words = generate(24).unwrap();
        assert_eq!(words.len(), 24);
        assert!(validate(&words));
    }

    #[test]
    fn test_invalid_word_count() {
        assert!(generate(15).is_err());
    }

    #[test]
    fn test_validate_invalid() {
        let words: Vec<String> = vec!["invalid"; 12].iter().map(|s| s.to_string()).collect();
        assert!(!validate(&words));
    }

    #[test]
    fn test_derive_deterministic() {
        let words: Vec<String> = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
            .split_whitespace()
            .map(String::from)
            .collect();
        let (pubkey1, seed1) = derive_keypair(&words, "").unwrap();
        let (pubkey2, seed2) = derive_keypair(&words, "").unwrap();
        assert_eq!(seed1, seed2);
        assert_eq!(pubkey1, pubkey2);
    }

    #[test]
    fn test_random_words() {
        let words = random_words(6);
        assert_eq!(words.len(), 6);
        // All should be valid BIP39 words
        let wordlist = Language::English.word_list();
        for w in &words {
            assert!(wordlist.contains(&w.as_str()), "'{w}' not in BIP39 wordlist");
        }
    }

    #[test]
    fn test_different_passphrase_different_key() {
        let words: Vec<String> = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
            .split_whitespace()
            .map(String::from)
            .collect();
        let (_, seed1) = derive_keypair(&words, "").unwrap();
        let (_, seed2) = derive_keypair(&words, "password").unwrap();
        assert_ne!(seed1, seed2);
    }
}
