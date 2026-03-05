use deadbolt_core::crypto::signer::TransactionSigner;
use deadbolt_core::hardware::esp32_bridge::Esp32Bridge;
use deadbolt_core::hardware::esp32_signer::Esp32Signer;
use deadbolt_core::solana::transaction::VersionedTransaction;

use super::types::SignedTxDto;
use super::wallet::manager_pub;

/// Sign a pre-built serialized transaction (base64-encoded).
///
/// Takes an unsigned (or partially-signed) VersionedTransaction from an
/// external source (Jupiter, DFlow, Sanctum, etc.), signs it with the
/// active wallet's keypair, and returns the signed base64 + first signature.
pub fn sign_serialized_transaction(
    unsigned_tx_base64: String,
) -> Result<SignedTxDto, String> {
    let mgr = manager_pub().read().map_err(|e| e.to_string())?;
    let signer = mgr.get_active_signer().map_err(|e| e.to_string())?;
    sign_tx_with(&unsigned_tx_base64, &signer)
}

/// Sign a pre-built serialized transaction via an ESP32 hardware wallet.
pub fn sign_serialized_transaction_hardware(
    port_path: String,
    unsigned_tx_base64: String,
) -> Result<SignedTxDto, String> {
    let bridge = Esp32Bridge::connect(&port_path).map_err(|e| e.to_string())?;
    let signer = Esp32Signer::new(bridge).map_err(|e| e.to_string())?;
    sign_tx_with(&unsigned_tx_base64, &signer)
}

fn sign_tx_with(
    unsigned_tx_base64: &str,
    signer: &dyn TransactionSigner,
) -> Result<SignedTxDto, String> {
    use base64::Engine;

    let tx_bytes = base64::engine::general_purpose::STANDARD
        .decode(unsigned_tx_base64)
        .map_err(|e| format!("Invalid base64: {e}"))?;

    let mut tx = VersionedTransaction::deserialize(&tx_bytes)
        .map_err(|e| format!("Failed to deserialize transaction: {e}"))?;

    tx.sign(signer).map_err(|e| format!("Signing failed: {e}"))?;

    let signature_bytes = tx.signatures.first()
        .ok_or_else(|| "No signatures in transaction".to_string())?;
    let signature_hex = hex::encode(signature_bytes);

    Ok(SignedTxDto {
        base64: tx.serialize_base64(),
        signature: signature_hex,
    })
}
