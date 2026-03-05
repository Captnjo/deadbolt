use rand::Rng;

use crate::crypto::SolanaPublicKey;
use crate::models::DeadboltError;
use crate::solana::instruction::Instruction;
use crate::solana::programs::system_program;

/// Jito tip account addresses — pick one at random for each transaction.
pub const TIP_ACCOUNTS: &[&str] = &[
    "96gYZGLnJYVFmbjzopPSU6QiEV5fGqZNyN9nmNhvrZU5",
    "HFqU5x63VTqvQss8hp11i4bVqkfRtQ7NmXwkiA8CBngy",
    "Cw8CFyM9FkoMi7K7Crf6HNQqf4uEMzpKw6QNghXLvLkY",
    "ADaUMid9yfUC67HyGE6d3hmtcpnxByUKTBNSNeqhPJ5X",
    "DfXygSm4jCyNCybVYYK6DwvWqjKee8pbDmJGcLWNDXjh",
    "ADuUkR4vqLUMWXxW9gh6D6L8pMSawimctcNZ5pGwDcEt",
    "DttWaMuVvTiduZRnguLF7jNxTgiMBZ1hyAumKUiL6d8u",
    "3AVi9Tg9Uo68tJfuvoKvqKNWKkC5wPdSSdeBnizKZ6jT",
];

/// Maximum allowed tip: 10,000,000 lamports (0.01 SOL).
pub const MAX_TIP_LAMPORTS: u64 = 10_000_000;

/// Default tip amount: 840,000 lamports (~0.00084 SOL).
pub const DEFAULT_TIP_LAMPORTS: u64 = 840_000;

/// Build a tip instruction (SOL transfer to a random Jito tip account).
pub fn tip_instruction(
    from: &SolanaPublicKey,
    lamports: u64,
) -> Result<Instruction, DeadboltError> {
    if lamports > MAX_TIP_LAMPORTS {
        return Err(DeadboltError::DecodingError(format!(
            "Jito tip {} lamports exceeds max {} lamports (0.01 SOL)",
            lamports, MAX_TIP_LAMPORTS
        )));
    }

    let mut rng = rand::thread_rng();
    let idx = rng.gen_range(0..TIP_ACCOUNTS.len());
    let tip_account = SolanaPublicKey::from_base58(TIP_ACCOUNTS[idx])?;

    Ok(system_program::transfer(from, &tip_account, lamports))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tip_instruction_default() {
        let from = SolanaPublicKey::from_bytes(&[1u8; 32]).unwrap();
        let ix = tip_instruction(&from, DEFAULT_TIP_LAMPORTS).unwrap();
        assert_eq!(ix.accounts.len(), 2);
    }

    #[test]
    fn test_tip_exceeds_max() {
        let from = SolanaPublicKey::from_bytes(&[1u8; 32]).unwrap();
        assert!(tip_instruction(&from, MAX_TIP_LAMPORTS + 1).is_err());
    }
}
