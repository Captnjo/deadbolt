use crate::crypto::signer::TransactionSigner;
use crate::crypto::SolanaPublicKey;
use crate::models::DeadboltError;
use crate::solana::instruction::Instruction;
use crate::solana::message::Message;
use crate::solana::programs::{compute_budget, jito_tip, system_program, token_program};
use crate::solana::transaction::Transaction;

/// Parameters for building a SOL transfer transaction.
pub struct SendSolParams {
    pub from: SolanaPublicKey,
    pub to: SolanaPublicKey,
    pub lamports: u64,
    pub recent_blockhash: String,
    pub compute_unit_limit: Option<u32>,
    pub compute_unit_price: Option<u64>,
    pub jito_tip_lamports: Option<u64>,
}

/// Parameters for building an SPL token transfer transaction.
pub struct SendTokenParams {
    pub from: SolanaPublicKey,
    pub to: SolanaPublicKey,
    pub mint: SolanaPublicKey,
    pub amount: u64,
    pub recent_blockhash: String,
    pub create_ata_if_needed: bool,
    pub compute_unit_limit: Option<u32>,
    pub compute_unit_price: Option<u64>,
    pub jito_tip_lamports: Option<u64>,
}

/// Result of building and signing a transaction.
pub struct SignedTransaction {
    /// Base64-encoded signed transaction, ready for RPC submission.
    pub base64: String,
    /// Transaction signature (first signature, hex-encoded).
    pub signature: String,
}

/// Build and sign a SOL transfer transaction.
pub fn build_and_sign_send_sol(
    params: &SendSolParams,
    signer: &dyn TransactionSigner,
) -> Result<SignedTransaction, DeadboltError> {
    let mut instructions: Vec<Instruction> = Vec::new();

    // Compute budget instructions (if specified)
    if let Some(limit) = params.compute_unit_limit {
        instructions.push(compute_budget::set_compute_unit_limit(limit));
    }
    if let Some(price) = params.compute_unit_price {
        instructions.push(compute_budget::set_compute_unit_price(price));
    }

    // Transfer instruction
    instructions.push(system_program::transfer(
        &params.from,
        &params.to,
        params.lamports,
    ));

    // Jito tip (if specified)
    if let Some(tip) = params.jito_tip_lamports {
        instructions.push(jito_tip::tip_instruction(&params.from, tip)?);
    }

    build_sign_legacy(instructions, &params.from, &params.recent_blockhash, signer)
}

/// Build and sign an SPL token transfer transaction.
pub fn build_and_sign_send_token(
    params: &SendTokenParams,
    signer: &dyn TransactionSigner,
) -> Result<SignedTransaction, DeadboltError> {
    let mut instructions: Vec<Instruction> = Vec::new();

    // Compute budget
    if let Some(limit) = params.compute_unit_limit {
        instructions.push(compute_budget::set_compute_unit_limit(limit));
    }
    if let Some(price) = params.compute_unit_price {
        instructions.push(compute_budget::set_compute_unit_price(price));
    }

    // Resolve ATAs
    let from_ata = token_program::associated_token_address(&params.from, &params.mint)?;
    let to_ata = token_program::associated_token_address(&params.to, &params.mint)?;

    // Create destination ATA if needed
    if params.create_ata_if_needed {
        instructions.push(token_program::create_associated_token_account(
            &params.from,
            &params.to,
            &params.mint,
        )?);
    }

    // SPL transfer
    instructions.push(token_program::transfer(
        &from_ata,
        &to_ata,
        &params.from,
        params.amount,
    ));

    // Jito tip
    if let Some(tip) = params.jito_tip_lamports {
        instructions.push(jito_tip::tip_instruction(&params.from, tip)?);
    }

    build_sign_legacy(instructions, &params.from, &params.recent_blockhash, signer)
}

/// Build an unsigned SOL transfer transaction (for simulation).
/// Returns base64-encoded transaction with zeroed signatures.
/// Use with simulateTransaction (sigVerify=false, replaceRecentBlockhash=true).
pub fn build_unsigned_send_sol(params: &SendSolParams) -> Result<String, DeadboltError> {
    let mut instructions: Vec<Instruction> = Vec::new();

    if let Some(limit) = params.compute_unit_limit {
        instructions.push(compute_budget::set_compute_unit_limit(limit));
    }
    if let Some(price) = params.compute_unit_price {
        instructions.push(compute_budget::set_compute_unit_price(price));
    }

    instructions.push(system_program::transfer(&params.from, &params.to, params.lamports));

    if let Some(tip) = params.jito_tip_lamports {
        instructions.push(jito_tip::tip_instruction(&params.from, tip)?);
    }

    build_unsigned_legacy(instructions, &params.from, &params.recent_blockhash)
}

/// Build an unsigned SPL token transfer transaction (for simulation).
/// Returns base64-encoded transaction with zeroed signatures.
/// Use with simulateTransaction (sigVerify=false, replaceRecentBlockhash=true).
pub fn build_unsigned_send_token(params: &SendTokenParams) -> Result<String, DeadboltError> {
    let mut instructions: Vec<Instruction> = Vec::new();

    if let Some(limit) = params.compute_unit_limit {
        instructions.push(compute_budget::set_compute_unit_limit(limit));
    }
    if let Some(price) = params.compute_unit_price {
        instructions.push(compute_budget::set_compute_unit_price(price));
    }

    let from_ata = token_program::associated_token_address(&params.from, &params.mint)?;
    let to_ata = token_program::associated_token_address(&params.to, &params.mint)?;

    if params.create_ata_if_needed {
        instructions.push(token_program::create_associated_token_account(
            &params.from,
            &params.to,
            &params.mint,
        )?);
    }

    instructions.push(token_program::transfer(
        &from_ata,
        &to_ata,
        &params.from,
        params.amount,
    ));

    if let Some(tip) = params.jito_tip_lamports {
        instructions.push(jito_tip::tip_instruction(&params.from, tip)?);
    }

    build_unsigned_legacy(instructions, &params.from, &params.recent_blockhash)
}

/// Build an unsigned legacy transaction and return base64.
/// Creates a transaction with zeroed signatures — suitable for simulation.
fn build_unsigned_legacy(
    instructions: Vec<Instruction>,
    fee_payer: &SolanaPublicKey,
    recent_blockhash: &str,
) -> Result<String, DeadboltError> {
    let message = Message::new(fee_payer, recent_blockhash, &instructions)?;
    let tx = Transaction::new(message); // zeroed signatures, no signing step
    Ok(tx.serialize_base64())
}

/// Build a legacy transaction from instructions, sign it, and return base64.
fn build_sign_legacy(
    instructions: Vec<Instruction>,
    fee_payer: &SolanaPublicKey,
    recent_blockhash: &str,
    signer: &dyn TransactionSigner,
) -> Result<SignedTransaction, DeadboltError> {
    let message = Message::new(fee_payer, recent_blockhash, &instructions)?;
    let mut tx = Transaction::new(message);
    tx.sign(signer)?;

    let signature = hex::encode(tx.signatures[0]);
    let base64 = tx.serialize_base64();

    Ok(SignedTransaction { base64, signature })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::signer::SoftwareSigner;

    fn test_signer() -> (SoftwareSigner, SolanaPublicKey) {
        let seed = [0x01u8; 32];
        let signer = SoftwareSigner::from_seed(&seed).unwrap();
        let pubkey = signer.public_key().clone();
        (signer, pubkey)
    }

    fn test_blockhash() -> String {
        "CVDFLCAjXhVWiPXH9nTCTpCgVzmDVoiPzNJYuccr1dqB".to_string()
    }

    #[test]
    fn test_build_send_sol_basic() {
        let (signer, from) = test_signer();
        let to = SolanaPublicKey::from_bytes(&[0x02u8; 32]).unwrap();

        let result = build_and_sign_send_sol(
            &SendSolParams {
                from,
                to,
                lamports: 1_000_000,
                recent_blockhash: test_blockhash(),
                compute_unit_limit: None,
                compute_unit_price: None,
                jito_tip_lamports: None,
            },
            &signer,
        )
        .unwrap();

        assert!(!result.base64.is_empty());
        assert_eq!(result.signature.len(), 128); // 64 bytes hex
    }

    #[test]
    fn test_build_send_sol_with_compute_budget() {
        let (signer, from) = test_signer();
        let to = SolanaPublicKey::from_bytes(&[0x02u8; 32]).unwrap();

        let result = build_and_sign_send_sol(
            &SendSolParams {
                from,
                to,
                lamports: 1_000_000,
                recent_blockhash: test_blockhash(),
                compute_unit_limit: Some(200_000),
                compute_unit_price: Some(50_000),
                jito_tip_lamports: None,
            },
            &signer,
        )
        .unwrap();

        assert!(!result.base64.is_empty());
    }

    #[test]
    fn test_build_send_sol_with_jito_tip() {
        let (signer, from) = test_signer();
        let to = SolanaPublicKey::from_bytes(&[0x02u8; 32]).unwrap();

        let result = build_and_sign_send_sol(
            &SendSolParams {
                from,
                to,
                lamports: 1_000_000,
                recent_blockhash: test_blockhash(),
                compute_unit_limit: Some(200_000),
                compute_unit_price: Some(50_000),
                jito_tip_lamports: Some(100_000),
            },
            &signer,
        )
        .unwrap();

        assert!(!result.base64.is_empty());
    }

    #[test]
    fn test_build_send_token_basic() {
        let (signer, from) = test_signer();
        let to = SolanaPublicKey::from_bytes(&[0x02u8; 32]).unwrap();
        let mint =
            SolanaPublicKey::from_base58("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
                .unwrap(); // USDC

        let result = build_and_sign_send_token(
            &SendTokenParams {
                from,
                to,
                mint,
                amount: 1_000_000, // 1 USDC
                recent_blockhash: test_blockhash(),
                create_ata_if_needed: false,
                compute_unit_limit: None,
                compute_unit_price: None,
                jito_tip_lamports: None,
            },
            &signer,
        )
        .unwrap();

        assert!(!result.base64.is_empty());
    }

    #[test]
    fn test_build_send_token_with_ata_creation() {
        let (signer, from) = test_signer();
        let to = SolanaPublicKey::from_bytes(&[0x02u8; 32]).unwrap();
        let mint =
            SolanaPublicKey::from_base58("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
                .unwrap();

        let result = build_and_sign_send_token(
            &SendTokenParams {
                from,
                to,
                mint,
                amount: 500_000,
                recent_blockhash: test_blockhash(),
                create_ata_if_needed: true,
                compute_unit_limit: Some(200_000),
                compute_unit_price: Some(50_000),
                jito_tip_lamports: None,
            },
            &signer,
        )
        .unwrap();

        assert!(!result.base64.is_empty());
    }

    #[test]
    fn test_signed_transaction_is_valid() {
        let (signer, from) = test_signer();
        let to = SolanaPublicKey::from_bytes(&[0x02u8; 32]).unwrap();

        let result = build_and_sign_send_sol(
            &SendSolParams {
                from: from.clone(),
                to,
                lamports: 42,
                recent_blockhash: test_blockhash(),
                compute_unit_limit: None,
                compute_unit_price: None,
                jito_tip_lamports: None,
            },
            &signer,
        )
        .unwrap();

        // Decode and verify signature
        use base64::Engine;
        let tx_bytes = base64::engine::general_purpose::STANDARD
            .decode(&result.base64)
            .unwrap();
        assert!(tx_bytes.len() > 64);

        // First bytes are compact-u16 sig count + 64-byte signature
        let sig_bytes: [u8; 64] = tx_bytes[1..65].try_into().unwrap();
        let msg_bytes = &tx_bytes[65..];

        assert!(SoftwareSigner::verify(&sig_bytes, msg_bytes, &from));
    }
}
