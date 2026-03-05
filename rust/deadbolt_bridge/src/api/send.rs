use deadbolt_core::crypto::signer::TransactionSigner;
use deadbolt_core::crypto::SolanaPublicKey;
use deadbolt_core::hardware::esp32_bridge::Esp32Bridge;
use deadbolt_core::hardware::esp32_signer::Esp32Signer;
use deadbolt_core::solana::builder::{self, SendSolParams, SendTokenParams};

use super::types::SignedTxDto;
use super::wallet::manager_pub;

/// Build and sign a SOL transfer transaction.
///
/// The active wallet must be unlocked first via `unlock_wallet`.
/// Returns the base64-encoded signed transaction and its signature.
pub fn sign_send_sol(
    to_address: String,
    lamports: u64,
    recent_blockhash: String,
    compute_unit_limit: Option<u32>,
    compute_unit_price: Option<u64>,
    jito_tip_lamports: Option<u64>,
) -> Result<SignedTxDto, String> {
    let mgr = manager_pub().read().map_err(|e| e.to_string())?;
    let signer = mgr.get_active_signer().map_err(|e| e.to_string())?;
    let from = signer.public_key().clone();
    let to = SolanaPublicKey::from_base58(&to_address).map_err(|e| e.to_string())?;

    let params = SendSolParams {
        from,
        to,
        lamports,
        recent_blockhash,
        compute_unit_limit,
        compute_unit_price,
        jito_tip_lamports,
    };

    let result = builder::build_and_sign_send_sol(&params, &signer).map_err(|e| e.to_string())?;

    Ok(SignedTxDto {
        base64: result.base64,
        signature: result.signature,
    })
}

/// Build and sign an SPL token transfer transaction.
///
/// The active wallet must be unlocked first via `unlock_wallet`.
/// ATAs are derived automatically. Set `create_ata_if_needed` to true
/// to include a CreateAssociatedTokenAccount instruction for the recipient.
pub fn sign_send_token(
    to_address: String,
    mint_address: String,
    amount: u64,
    recent_blockhash: String,
    create_ata_if_needed: bool,
    compute_unit_limit: Option<u32>,
    compute_unit_price: Option<u64>,
    jito_tip_lamports: Option<u64>,
) -> Result<SignedTxDto, String> {
    let mgr = manager_pub().read().map_err(|e| e.to_string())?;
    let signer = mgr.get_active_signer().map_err(|e| e.to_string())?;
    let from = signer.public_key().clone();
    let to = SolanaPublicKey::from_base58(&to_address).map_err(|e| e.to_string())?;
    let mint = SolanaPublicKey::from_base58(&mint_address).map_err(|e| e.to_string())?;

    let params = SendTokenParams {
        from,
        to,
        mint,
        amount,
        recent_blockhash,
        create_ata_if_needed,
        compute_unit_limit,
        compute_unit_price,
        jito_tip_lamports,
    };

    let result =
        builder::build_and_sign_send_token(&params, &signer).map_err(|e| e.to_string())?;

    Ok(SignedTxDto {
        base64: result.base64,
        signature: result.signature,
    })
}

// ─── Hardware wallet signing (ESP32) ───

/// Connect to an ESP32 at the given port and return an Esp32Signer.
fn esp32_signer(port_path: &str) -> Result<Esp32Signer, String> {
    let bridge = Esp32Bridge::connect(port_path).map_err(|e| e.to_string())?;
    Esp32Signer::new(bridge).map_err(|e| e.to_string())
}

/// Build and sign a SOL transfer via an ESP32 hardware wallet.
///
/// Connects to the ESP32 at `port_path`, builds the transaction, then the
/// device LED pulses and the user must press BOOT within 30 seconds.
pub fn sign_send_sol_hardware(
    port_path: String,
    to_address: String,
    lamports: u64,
    recent_blockhash: String,
    compute_unit_limit: Option<u32>,
    compute_unit_price: Option<u64>,
    jito_tip_lamports: Option<u64>,
) -> Result<SignedTxDto, String> {
    let signer = esp32_signer(&port_path)?;
    let from = signer.public_key().clone();
    let to = SolanaPublicKey::from_base58(&to_address).map_err(|e| e.to_string())?;

    let params = SendSolParams {
        from,
        to,
        lamports,
        recent_blockhash,
        compute_unit_limit,
        compute_unit_price,
        jito_tip_lamports,
    };

    let result = builder::build_and_sign_send_sol(&params, &signer).map_err(|e| e.to_string())?;

    Ok(SignedTxDto {
        base64: result.base64,
        signature: result.signature,
    })
}

/// Build and sign an SPL token transfer via an ESP32 hardware wallet.
pub fn sign_send_token_hardware(
    port_path: String,
    to_address: String,
    mint_address: String,
    amount: u64,
    recent_blockhash: String,
    create_ata_if_needed: bool,
    compute_unit_limit: Option<u32>,
    compute_unit_price: Option<u64>,
    jito_tip_lamports: Option<u64>,
) -> Result<SignedTxDto, String> {
    let signer = esp32_signer(&port_path)?;
    let from = signer.public_key().clone();
    let to = SolanaPublicKey::from_base58(&to_address).map_err(|e| e.to_string())?;
    let mint = SolanaPublicKey::from_base58(&mint_address).map_err(|e| e.to_string())?;

    let params = SendTokenParams {
        from,
        to,
        mint,
        amount,
        recent_blockhash,
        create_ata_if_needed,
        compute_unit_limit,
        compute_unit_price,
        jito_tip_lamports,
    };

    let result =
        builder::build_and_sign_send_token(&params, &signer).map_err(|e| e.to_string())?;

    Ok(SignedTxDto {
        base64: result.base64,
        signature: result.signature,
    })
}
