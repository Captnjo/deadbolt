use crate::crypto::SolanaPublicKey;

/// A single Solana instruction to be included in a transaction message.
#[derive(Debug, Clone)]
pub struct Instruction {
    pub program_id: SolanaPublicKey,
    pub accounts: Vec<AccountMeta>,
    pub data: Vec<u8>,
}

/// Account metadata for an instruction.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AccountMeta {
    pub pubkey: SolanaPublicKey,
    pub is_signer: bool,
    pub is_writable: bool,
}

/// A compiled instruction with account indices instead of full public keys.
#[derive(Debug, Clone)]
pub struct CompiledInstruction {
    pub program_id_index: u8,
    pub account_indices: Vec<u8>,
    pub data: Vec<u8>,
}

impl CompiledInstruction {
    pub fn serialize(&self) -> Vec<u8> {
        use super::compact_u16;
        let mut out = Vec::new();
        out.push(self.program_id_index);
        out.extend_from_slice(&compact_u16::encode(self.account_indices.len() as u16));
        out.extend_from_slice(&self.account_indices);
        out.extend_from_slice(&compact_u16::encode(self.data.len() as u16));
        out.extend_from_slice(&self.data);
        out
    }

    pub fn deserialize(data: &[u8], offset: &mut usize) -> Result<Self, crate::models::DeadboltError> {
        use super::compact_u16;

        if *offset >= data.len() {
            return Err(crate::models::DeadboltError::DecodingError(
                "Not enough bytes for instruction programIdIndex".into(),
            ));
        }
        let program_id_index = data[*offset];
        *offset += 1;

        let (acct_count, acct_bytes) = compact_u16::decode(data, *offset)?;
        *offset += acct_bytes;

        if *offset + acct_count as usize > data.len() {
            return Err(crate::models::DeadboltError::DecodingError(
                "Not enough bytes for instruction account indices".into(),
            ));
        }
        let account_indices = data[*offset..*offset + acct_count as usize].to_vec();
        *offset += acct_count as usize;

        let (data_len, data_len_bytes) = compact_u16::decode(data, *offset)?;
        *offset += data_len_bytes;

        if *offset + data_len as usize > data.len() {
            return Err(crate::models::DeadboltError::DecodingError(
                "Not enough bytes for instruction data".into(),
            ));
        }
        let ix_data = data[*offset..*offset + data_len as usize].to_vec();
        *offset += data_len as usize;

        Ok(Self {
            program_id_index,
            account_indices,
            data: ix_data,
        })
    }
}
