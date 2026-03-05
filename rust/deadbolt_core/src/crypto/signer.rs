use ed25519_dalek::{Signer, SigningKey, VerifyingKey};
use zeroize::ZeroizeOnDrop;

use super::pubkey::SolanaPublicKey;
use crate::models::DeadboltError;

/// Trait for anything that can sign Solana transaction messages.
pub trait TransactionSigner: Send + Sync {
    fn public_key(&self) -> &SolanaPublicKey;
    fn sign(&self, message: &[u8]) -> Result<[u8; 64], DeadboltError>;
}

/// Software signer using ed25519-dalek.
/// SigningKey from ed25519-dalek already implements Zeroize internally.
#[derive(ZeroizeOnDrop)]
pub struct SoftwareSigner {
    signing_key: SigningKey,
    #[zeroize(skip)]
    pubkey: SolanaPublicKey,
}

impl SoftwareSigner {
    /// Create from a 32-byte Ed25519 seed.
    pub fn from_seed(seed: &[u8; 32]) -> Result<Self, DeadboltError> {
        let signing_key = SigningKey::from_bytes(seed);
        let verifying_key = signing_key.verifying_key();
        let pubkey = SolanaPublicKey::from_bytes(verifying_key.as_bytes())?;
        Ok(Self { signing_key, pubkey })
    }

    /// Create from a 64-byte keypair (seed + pubkey), verifying they match.
    pub fn from_keypair_bytes(keypair: &[u8]) -> Result<Self, DeadboltError> {
        if keypair.len() != 64 {
            return Err(DeadboltError::InvalidKeypairLength(keypair.len()));
        }
        let seed: [u8; 32] = keypair[..32].try_into().unwrap();
        let expected_pub: [u8; 32] = keypair[32..].try_into().unwrap();

        let signing_key = SigningKey::from_bytes(&seed);
        let verifying_key = signing_key.verifying_key();

        if verifying_key.as_bytes() != &expected_pub {
            return Err(DeadboltError::PublicKeyMismatch);
        }

        let pubkey = SolanaPublicKey::from_bytes(verifying_key.as_bytes())?;
        Ok(Self { signing_key, pubkey })
    }

    /// Verify a signature against a message and public key.
    pub fn verify(signature: &[u8; 64], message: &[u8], pubkey: &SolanaPublicKey) -> bool {
        let Ok(verifying_key) = VerifyingKey::from_bytes(pubkey.as_bytes()) else {
            return false;
        };
        let sig = ed25519_dalek::Signature::from_bytes(signature);
        verifying_key.verify_strict(message, &sig).is_ok()
    }
}

impl TransactionSigner for SoftwareSigner {
    fn public_key(&self) -> &SolanaPublicKey {
        &self.pubkey
    }

    fn sign(&self, message: &[u8]) -> Result<[u8; 64], DeadboltError> {
        let sig = self.signing_key.sign(message);
        Ok(sig.to_bytes())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sign_and_verify() {
        let seed = [42u8; 32];
        let signer = SoftwareSigner::from_seed(&seed).unwrap();
        let message = b"hello solana";
        let signature = signer.sign(message).unwrap();
        assert!(SoftwareSigner::verify(&signature, message, signer.public_key()));
    }

    #[test]
    fn test_wrong_message_fails_verify() {
        let seed = [42u8; 32];
        let signer = SoftwareSigner::from_seed(&seed).unwrap();
        let signature = signer.sign(b"hello").unwrap();
        assert!(!SoftwareSigner::verify(&signature, b"wrong", signer.public_key()));
    }

    #[test]
    fn test_from_keypair_bytes_mismatch() {
        let mut keypair = [0u8; 64];
        keypair[..32].copy_from_slice(&[42u8; 32]);
        keypair[32..].copy_from_slice(&[0u8; 32]); // wrong pubkey
        assert!(SoftwareSigner::from_keypair_bytes(&keypair).is_err());
    }
}
