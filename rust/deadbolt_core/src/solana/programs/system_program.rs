use crate::crypto::SolanaPublicKey;
use crate::solana::instruction::{AccountMeta, Instruction};

pub fn program_id() -> SolanaPublicKey {
    SolanaPublicKey::from_base58("11111111111111111111111111111111").unwrap()
}

/// Transfer lamports from one account to another.
/// Instruction data: u32 instruction index (2 = transfer) + u64 lamports (little-endian)
pub fn transfer(
    from: &SolanaPublicKey,
    to: &SolanaPublicKey,
    lamports: u64,
) -> Instruction {
    let mut data = vec![0u8; 12];
    // Instruction index 2 = Transfer (little-endian u32)
    data[0] = 2;
    data[4..12].copy_from_slice(&lamports.to_le_bytes());

    Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta {
                pubkey: from.clone(),
                is_signer: true,
                is_writable: true,
            },
            AccountMeta {
                pubkey: to.clone(),
                is_signer: false,
                is_writable: true,
            },
        ],
        data,
    }
}
