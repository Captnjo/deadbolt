use crate::crypto::TransactionSigner;
use crate::models::DeadboltError;

use super::compact_u16;
use super::message::Message;
use super::versioned_message::VersionedMessage;

/// A Solana legacy transaction: signature(s) + serialized message.
#[derive(Debug, Clone)]
pub struct Transaction {
    pub message: Message,
    pub signatures: Vec<[u8; 64]>,
}

impl Transaction {
    /// Create an unsigned transaction from a message.
    pub fn new(message: Message) -> Self {
        let num_signers = message.header.num_required_signatures as usize;
        Self {
            signatures: vec![[0u8; 64]; num_signers],
            message,
        }
    }

    /// Sign the transaction with a signer.
    pub fn sign(&mut self, signer: &dyn TransactionSigner) -> Result<(), DeadboltError> {
        let message_data = self.message.serialize();
        let signature = signer.sign(&message_data)?;

        let num_signers = self.message.header.num_required_signatures as usize;
        let signer_index = self
            .message
            .account_keys
            .iter()
            .take(num_signers)
            .position(|k| k == signer.public_key())
            .ok_or_else(|| {
                DeadboltError::DecodingError(format!(
                    "Signer {} not found in required signers",
                    signer.public_key()
                ))
            })?;

        self.signatures[signer_index] = signature;
        Ok(())
    }

    /// Serialize the full transaction to wire format.
    pub fn serialize(&self) -> Vec<u8> {
        let mut data = Vec::new();
        data.extend_from_slice(&compact_u16::encode(self.signatures.len() as u16));
        for sig in &self.signatures {
            data.extend_from_slice(sig);
        }
        data.extend_from_slice(&self.message.serialize());
        data
    }

    /// Serialize to base64 for RPC submission.
    pub fn serialize_base64(&self) -> String {
        use base64::Engine;
        base64::engine::general_purpose::STANDARD.encode(self.serialize())
    }
}

/// A Solana versioned transaction supporting both legacy and v0 message formats.
#[derive(Debug, Clone)]
pub struct VersionedTransaction {
    pub message: VersionedMessage,
    pub signatures: Vec<[u8; 64]>,
}

impl VersionedTransaction {
    /// Create an unsigned versioned transaction from a message.
    pub fn new(message: VersionedMessage) -> Self {
        let num_signers = message.header().num_required_signatures as usize;
        Self {
            signatures: vec![[0u8; 64]; num_signers],
            message,
        }
    }

    /// Create with pre-existing signatures (for deserialization).
    pub fn with_signatures(message: VersionedMessage, signatures: Vec<[u8; 64]>) -> Self {
        Self {
            message,
            signatures,
        }
    }

    /// Sign the transaction with a signer.
    pub fn sign(&mut self, signer: &dyn TransactionSigner) -> Result<(), DeadboltError> {
        let message_data = self.message.serialize();
        let signature = signer.sign(&message_data)?;

        let account_keys = self.message.account_keys();
        let num_signers = self.message.header().num_required_signatures as usize;

        let signer_index = account_keys
            .iter()
            .take(num_signers)
            .position(|k| k == signer.public_key())
            .ok_or_else(|| {
                DeadboltError::DecodingError(format!(
                    "Signer {} not found in required signers",
                    signer.public_key()
                ))
            })?;

        self.signatures[signer_index] = signature;
        Ok(())
    }

    /// Deserialize a VersionedTransaction from wire format bytes.
    pub fn deserialize(data: &[u8]) -> Result<Self, DeadboltError> {
        let mut offset = 0;

        let (sig_count, sig_count_bytes) = compact_u16::decode(data, offset)?;
        offset += sig_count_bytes;

        let mut signatures = Vec::with_capacity(sig_count as usize);
        for _ in 0..sig_count {
            if offset + 64 > data.len() {
                return Err(DeadboltError::DecodingError(
                    "Not enough bytes for signature".into(),
                ));
            }
            let mut sig = [0u8; 64];
            sig.copy_from_slice(&data[offset..offset + 64]);
            signatures.push(sig);
            offset += 64;
        }

        let message = VersionedMessage::deserialize(data, &mut offset)?;

        Ok(Self {
            message,
            signatures,
        })
    }

    /// Serialize the full transaction to wire format.
    pub fn serialize(&self) -> Vec<u8> {
        let mut data = Vec::new();
        data.extend_from_slice(&compact_u16::encode(self.signatures.len() as u16));
        for sig in &self.signatures {
            data.extend_from_slice(sig);
        }
        data.extend_from_slice(&self.message.serialize());
        data
    }

    /// Serialize to base64 for RPC submission.
    pub fn serialize_base64(&self) -> String {
        use base64::Engine;
        base64::engine::general_purpose::STANDARD.encode(self.serialize())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::{SoftwareSigner, SolanaPublicKey};
    use crate::solana::programs::system_program;

    #[test]
    fn test_create_and_sign_legacy_transaction() {
        let seed = [1u8; 32];
        let signer = SoftwareSigner::from_seed(&seed).unwrap();
        let fee_payer = signer.public_key().clone();

        let recipient = SolanaPublicKey::from_bytes(&[2u8; 32]).unwrap();
        let blockhash = "11111111111111111111111111111111";

        let ix = system_program::transfer(&fee_payer, &recipient, 1_000_000);
        let message = Message::new(&fee_payer, blockhash, &[ix]).unwrap();
        let mut tx = Transaction::new(message);

        tx.sign(&signer).unwrap();

        // Signature should no longer be all zeros
        assert_ne!(tx.signatures[0], [0u8; 64]);

        // Serialize/deserialize round-trip
        let serialized = tx.serialize();
        assert!(!serialized.is_empty());
    }

    #[test]
    fn test_versioned_transaction_deserialize_roundtrip() {
        let seed = [1u8; 32];
        let signer = SoftwareSigner::from_seed(&seed).unwrap();
        let fee_payer = signer.public_key().clone();

        let recipient = SolanaPublicKey::from_bytes(&[2u8; 32]).unwrap();
        let blockhash = "11111111111111111111111111111111";

        let ix = system_program::transfer(&fee_payer, &recipient, 500_000);
        let message = Message::new(&fee_payer, blockhash, &[ix]).unwrap();
        let versioned = VersionedMessage::Legacy(message);
        let mut tx = VersionedTransaction::new(versioned);
        tx.sign(&signer).unwrap();

        let serialized = tx.serialize();
        let deserialized = VersionedTransaction::deserialize(&serialized).unwrap();

        assert_eq!(deserialized.signatures.len(), tx.signatures.len());
        assert_eq!(deserialized.signatures[0], tx.signatures[0]);
    }
}
