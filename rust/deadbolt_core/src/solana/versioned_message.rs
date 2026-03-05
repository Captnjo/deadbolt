use crate::crypto::SolanaPublicKey;
use crate::models::DeadboltError;

use super::compact_u16;
use super::instruction::CompiledInstruction;
use super::message::{Message, MessageHeader};

/// An address table lookup entry in a v0 message.
#[derive(Debug, Clone)]
pub struct MessageAddressTableLookup {
    pub account_key: SolanaPublicKey,
    pub writable_indexes: Vec<u8>,
    pub readonly_indexes: Vec<u8>,
}

/// Solana v0 transaction message with address lookup table support.
#[derive(Debug, Clone)]
pub struct V0Message {
    pub header: MessageHeader,
    pub account_keys: Vec<SolanaPublicKey>,
    pub recent_blockhash: [u8; 32],
    pub instructions: Vec<CompiledInstruction>,
    pub address_table_lookups: Vec<MessageAddressTableLookup>,
}

impl V0Message {
    /// Deserialize a V0 message from wire format bytes.
    /// The caller must have already consumed the 0x80 version prefix byte.
    pub fn deserialize(data: &[u8], offset: &mut usize) -> Result<Self, DeadboltError> {
        if *offset + 3 > data.len() {
            return Err(DeadboltError::DecodingError(
                "Not enough bytes for v0 message header".into(),
            ));
        }

        let header = MessageHeader {
            num_required_signatures: data[*offset],
            num_readonly_signed_accounts: data[*offset + 1],
            num_readonly_unsigned_accounts: data[*offset + 2],
        };
        *offset += 3;

        // Static account keys
        let (key_count, key_count_bytes) = compact_u16::decode(data, *offset)?;
        *offset += key_count_bytes;

        let mut keys = Vec::with_capacity(key_count as usize);
        for _ in 0..key_count {
            if *offset + 32 > data.len() {
                return Err(DeadboltError::DecodingError(
                    "Not enough bytes for account key in v0 message".into(),
                ));
            }
            keys.push(SolanaPublicKey::from_bytes(&data[*offset..*offset + 32])?);
            *offset += 32;
        }

        // Recent blockhash
        if *offset + 32 > data.len() {
            return Err(DeadboltError::DecodingError(
                "Not enough bytes for blockhash in v0 message".into(),
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

        // Address table lookups
        let (alt_count, alt_count_bytes) = compact_u16::decode(data, *offset)?;
        *offset += alt_count_bytes;

        let mut lookups = Vec::with_capacity(alt_count as usize);
        for _ in 0..alt_count {
            if *offset + 32 > data.len() {
                return Err(DeadboltError::DecodingError(
                    "Not enough bytes for ALT account key".into(),
                ));
            }
            let account_key = SolanaPublicKey::from_bytes(&data[*offset..*offset + 32])?;
            *offset += 32;

            // Writable indexes
            let (writable_count, wc_bytes) = compact_u16::decode(data, *offset)?;
            *offset += wc_bytes;
            if *offset + writable_count as usize > data.len() {
                return Err(DeadboltError::DecodingError(
                    "Not enough bytes for ALT writable indexes".into(),
                ));
            }
            let writable_indexes = data[*offset..*offset + writable_count as usize].to_vec();
            *offset += writable_count as usize;

            // Readonly indexes
            let (readonly_count, rc_bytes) = compact_u16::decode(data, *offset)?;
            *offset += rc_bytes;
            if *offset + readonly_count as usize > data.len() {
                return Err(DeadboltError::DecodingError(
                    "Not enough bytes for ALT readonly indexes".into(),
                ));
            }
            let readonly_indexes = data[*offset..*offset + readonly_count as usize].to_vec();
            *offset += readonly_count as usize;

            lookups.push(MessageAddressTableLookup {
                account_key,
                writable_indexes,
                readonly_indexes,
            });
        }

        Ok(Self {
            header,
            account_keys: keys,
            recent_blockhash: blockhash,
            instructions,
            address_table_lookups: lookups,
        })
    }

    /// Serialize the v0 message to wire format bytes.
    pub fn serialize(&self) -> Vec<u8> {
        let mut data = Vec::new();

        // Version prefix: 0x80 for v0
        data.push(0x80);

        // Header
        data.push(self.header.num_required_signatures);
        data.push(self.header.num_readonly_signed_accounts);
        data.push(self.header.num_readonly_unsigned_accounts);

        // Static account keys
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

        // Address table lookups
        data.extend_from_slice(&compact_u16::encode(
            self.address_table_lookups.len() as u16,
        ));
        for lookup in &self.address_table_lookups {
            data.extend_from_slice(lookup.account_key.as_bytes());
            data.extend_from_slice(&compact_u16::encode(lookup.writable_indexes.len() as u16));
            data.extend_from_slice(&lookup.writable_indexes);
            data.extend_from_slice(&compact_u16::encode(lookup.readonly_indexes.len() as u16));
            data.extend_from_slice(&lookup.readonly_indexes);
        }

        data
    }
}

/// A Solana transaction message that can be either legacy or v0 format.
#[derive(Debug, Clone)]
pub enum VersionedMessage {
    Legacy(Message),
    V0(V0Message),
}

impl VersionedMessage {
    /// Deserialize a versioned message from wire format bytes.
    pub fn deserialize(data: &[u8], offset: &mut usize) -> Result<Self, DeadboltError> {
        if *offset >= data.len() {
            return Err(DeadboltError::DecodingError(
                "No bytes available for message deserialization".into(),
            ));
        }

        let first_byte = data[*offset];

        if first_byte & 0x80 != 0 {
            // V0 message: consume the 0x80 prefix byte
            *offset += 1;
            let v0 = V0Message::deserialize(data, offset)?;
            Ok(VersionedMessage::V0(v0))
        } else {
            // Legacy message
            let msg = Message::deserialize(data, offset)?;
            Ok(VersionedMessage::Legacy(msg))
        }
    }

    /// Serialize the message to wire format bytes.
    pub fn serialize(&self) -> Vec<u8> {
        match self {
            VersionedMessage::Legacy(msg) => msg.serialize(),
            VersionedMessage::V0(msg) => msg.serialize(),
        }
    }

    pub fn header(&self) -> &MessageHeader {
        match self {
            VersionedMessage::Legacy(msg) => &msg.header,
            VersionedMessage::V0(msg) => &msg.header,
        }
    }

    pub fn account_keys(&self) -> &[SolanaPublicKey] {
        match self {
            VersionedMessage::Legacy(msg) => &msg.account_keys,
            VersionedMessage::V0(msg) => &msg.account_keys,
        }
    }
}
