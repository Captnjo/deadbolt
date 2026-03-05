use crate::crypto::SolanaPublicKey;
use crate::models::DeadboltError;
use crate::solana::instruction::{AccountMeta, Instruction};
use crate::solana::pda;
use crate::solana::programs::system_program;

pub fn program_id() -> SolanaPublicKey {
    SolanaPublicKey::from_base58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA").unwrap()
}

pub fn associated_token_program_id() -> SolanaPublicKey {
    SolanaPublicKey::from_base58("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL").unwrap()
}

/// Transfer SPL tokens from one token account to another.
pub fn transfer(
    source: &SolanaPublicKey,
    destination: &SolanaPublicKey,
    owner: &SolanaPublicKey,
    amount: u64,
) -> Instruction {
    let mut data = vec![0u8; 9];
    data[0] = 3; // Transfer instruction variant
    data[1..9].copy_from_slice(&amount.to_le_bytes());

    Instruction {
        program_id: program_id(),
        accounts: vec![
            AccountMeta {
                pubkey: source.clone(),
                is_signer: false,
                is_writable: true,
            },
            AccountMeta {
                pubkey: destination.clone(),
                is_signer: false,
                is_writable: true,
            },
            AccountMeta {
                pubkey: owner.clone(),
                is_signer: true,
                is_writable: false,
            },
        ],
        data,
    }
}

/// Create an associated token account for the given owner and mint.
pub fn create_associated_token_account(
    payer: &SolanaPublicKey,
    owner: &SolanaPublicKey,
    mint: &SolanaPublicKey,
) -> Result<Instruction, DeadboltError> {
    let ata = associated_token_address(owner, mint)?;

    Ok(Instruction {
        program_id: associated_token_program_id(),
        accounts: vec![
            AccountMeta {
                pubkey: payer.clone(),
                is_signer: true,
                is_writable: true,
            },
            AccountMeta {
                pubkey: ata,
                is_signer: false,
                is_writable: true,
            },
            AccountMeta {
                pubkey: owner.clone(),
                is_signer: false,
                is_writable: false,
            },
            AccountMeta {
                pubkey: mint.clone(),
                is_signer: false,
                is_writable: false,
            },
            AccountMeta {
                pubkey: system_program::program_id(),
                is_signer: false,
                is_writable: false,
            },
            AccountMeta {
                pubkey: program_id(),
                is_signer: false,
                is_writable: false,
            },
        ],
        data: Vec::new(),
    })
}

/// Derive the associated token address for a given owner and mint.
pub fn associated_token_address(
    owner: &SolanaPublicKey,
    mint: &SolanaPublicKey,
) -> Result<SolanaPublicKey, DeadboltError> {
    let (address, _) = pda::find_program_address(
        &[
            owner.as_bytes(),
            program_id().as_bytes(),
            mint.as_bytes(),
        ],
        &associated_token_program_id(),
    )?;
    Ok(address)
}
