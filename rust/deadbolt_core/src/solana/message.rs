use std::collections::HashMap;

use crate::crypto::base58;
use crate::crypto::SolanaPublicKey;
use crate::models::DeadboltError;

use super::compact_u16;
use super::instruction::{CompiledInstruction, Instruction};

#[derive(Debug, Clone, Copy)]
pub struct MessageHeader {
    pub num_required_signatures: u8,
    pub num_readonly_signed_accounts: u8,
    pub num_readonly_unsigned_accounts: u8,
}

/// Solana legacy transaction message.
#[derive(Debug, Clone)]
pub struct Message {
    pub header: MessageHeader,
    pub account_keys: Vec<SolanaPublicKey>,
    pub recent_blockhash: [u8; 32],
    pub instructions: Vec<CompiledInstruction>,
}

impl Message {
    /// Build a Message from high-level instructions, automatically computing the header,
    /// deduplicating + ordering account keys, and compiling instruction indices.
    pub fn new(
        fee_payer: &SolanaPublicKey,
        recent_blockhash: &str,
        instructions: &[Instruction],
    ) -> Result<Self, DeadboltError> {
        let blockhash_data = base58::decode(recent_blockhash)?;
        if blockhash_data.len() != 32 {
            return Err(DeadboltError::DecodingError(format!(
                "Invalid blockhash length: {}",
                blockhash_data.len()
            )));
        }
        let mut blockhash = [0u8; 32];
        blockhash.copy_from_slice(&blockhash_data);

        // Collect all unique accounts with their highest privilege level
        let mut account_map: HashMap<SolanaPublicKey, (bool, bool)> = HashMap::new(); // (is_signer, is_writable)

        // Fee payer is always signer + writable
        account_map.insert(fee_payer.clone(), (true, true));

        for ix in instructions {
            let entry = account_map.entry(ix.program_id.clone()).or_insert((false, false));
            // Program ID is read-only, non-signer (keep existing privileges)
            let _ = entry;

            for acct in &ix.accounts {
                let entry = account_map.entry(acct.pubkey.clone()).or_insert((false, false));
                entry.0 |= acct.is_signer;
                entry.1 |= acct.is_writable;
            }
        }

        // Sort accounts into categories
        let mut signer_writable: Vec<SolanaPublicKey> = Vec::new();
        let mut signer_readonly: Vec<SolanaPublicKey> = Vec::new();
        let mut nonsigner_writable: Vec<SolanaPublicKey> = Vec::new();
        let mut nonsigner_readonly: Vec<SolanaPublicKey> = Vec::new();

        for (key, (is_signer, is_writable)) in &account_map {
            if key == fee_payer {
                continue;
            }
            match (is_signer, is_writable) {
                (true, true) => signer_writable.push(key.clone()),
                (true, false) => signer_readonly.push(key.clone()),
                (false, true) => nonsigner_writable.push(key.clone()),
                (false, false) => nonsigner_readonly.push(key.clone()),
            }
        }

        // Sort each group by public key bytes for deterministic ordering
        signer_writable.sort();
        signer_readonly.sort();
        nonsigner_writable.sort();
        nonsigner_readonly.sort();

        let mut ordered_keys = vec![fee_payer.clone()];
        ordered_keys.extend(signer_writable);
        ordered_keys.extend(signer_readonly.clone());
        ordered_keys.extend(nonsigner_writable);
        ordered_keys.extend(nonsigner_readonly.clone());

        let num_required_signatures = 1 + account_map.iter()
            .filter(|(k, (s, _))| *k != fee_payer && *s)
            .count();

        // Build account index lookup
        let key_index: HashMap<SolanaPublicKey, u8> = ordered_keys
            .iter()
            .enumerate()
            .map(|(i, k)| (k.clone(), i as u8))
            .collect();

        // Compile instructions
        let mut compiled = Vec::new();
        for ix in instructions {
            let program_id_index = *key_index
                .get(&ix.program_id)
                .ok_or_else(|| DeadboltError::DecodingError("Program ID not found".into()))?;
            let account_indices: Result<Vec<u8>, _> = ix
                .accounts
                .iter()
                .map(|acct| {
                    key_index
                        .get(&acct.pubkey)
                        .copied()
                        .ok_or_else(|| {
                            DeadboltError::DecodingError(format!(
                                "Account not found: {}",
                                acct.pubkey
                            ))
                        })
                })
                .collect();
            compiled.push(CompiledInstruction {
                program_id_index,
                account_indices: account_indices?,
                data: ix.data.clone(),
            });
        }

        Ok(Self {
            header: MessageHeader {
                num_required_signatures: num_required_signatures as u8,
                num_readonly_signed_accounts: signer_readonly.len() as u8,
                num_readonly_unsigned_accounts: nonsigner_readonly.len() as u8,
            },
            account_keys: ordered_keys,
            recent_blockhash: blockhash,
            instructions: compiled,
        })
    }

    /// Deserialize a legacy message from wire format bytes.
    pub fn deserialize(data: &[u8], offset: &mut usize) -> Result<Self, DeadboltError> {
        if *offset + 3 > data.len() {
            return Err(DeadboltError::DecodingError(
                "Not enough bytes for legacy message header".into(),
            ));
        }

        let header = MessageHeader {
            num_required_signatures: data[*offset],
            num_readonly_signed_accounts: data[*offset + 1],
            num_readonly_unsigned_accounts: data[*offset + 2],
        };
        *offset += 3;

        // Account keys
        let (key_count, key_count_bytes) = compact_u16::decode(data, *offset)?;
        *offset += key_count_bytes;

        let mut keys = Vec::with_capacity(key_count as usize);
        for _ in 0..key_count {
            if *offset + 32 > data.len() {
                return Err(DeadboltError::DecodingError(
                    "Not enough bytes for account key".into(),
                ));
            }
            keys.push(SolanaPublicKey::from_bytes(&data[*offset..*offset + 32])?);
            *offset += 32;
        }

        // Recent blockhash
        if *offset + 32 > data.len() {
            return Err(DeadboltError::DecodingError(
                "Not enough bytes for blockhash".into(),
            ));
        }
        let mut blockhash = [0u8; 32];
        blockhash.copy_from_slice(&data[*offset..*offset + 32]);
        *offset += 32;

        // Instructions
        let (ix_count, ix_count_bytes) = compact_u16::decode(data, *offset)?;
        *offset += ix_count_bytes;

        let mut instructions = Vec::with_capacity(ix_count as usize);
        for _ in 0..ix_count {
            instructions.push(CompiledInstruction::deserialize(data, offset)?);
        }

        Ok(Self {
            header,
            account_keys: keys,
            recent_blockhash: blockhash,
            instructions,
        })
    }

    /// Serialize the message to wire format bytes.
    pub fn serialize(&self) -> Vec<u8> {
        let mut data = Vec::new();

        // Header: 3 bytes
        data.push(self.header.num_required_signatures);
        data.push(self.header.num_readonly_signed_accounts);
        data.push(self.header.num_readonly_unsigned_accounts);

        // Account keys
        data.extend_from_slice(&compact_u16::encode(self.account_keys.len() as u16));
        for key in &self.account_keys {
            data.extend_from_slice(key.as_bytes());
        }

        // Recent blockhash
        data.extend_from_slice(&self.recent_blockhash);

        // Instructions
        data.extend_from_slice(&compact_u16::encode(self.instructions.len() as u16));
        for ix in &self.instructions {
            data.extend_from_slice(&ix.serialize());
        }

        data
    }
}
