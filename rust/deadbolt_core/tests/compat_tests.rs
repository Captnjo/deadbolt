//! Tests ported from Swift DeadboltCore for cross-platform compatibility.
//! Test vectors verified byte-for-byte against @solana/web3.js 1.91.4.

use deadbolt_core::crypto::base58;
use deadbolt_core::crypto::mnemonic;
use deadbolt_core::crypto::pubkey::SolanaPublicKey;
use deadbolt_core::crypto::signer::SoftwareSigner;
use deadbolt_core::crypto::TransactionSigner;
use deadbolt_core::solana::compact_u16;
use deadbolt_core::solana::message::Message;
use deadbolt_core::solana::pda;
use deadbolt_core::solana::programs::{compute_budget, jito_tip, system_program, token_program};
use deadbolt_core::solana::transaction::Transaction;

// ─── Base58 ─────────────────────────────────────────────────────────────

#[test]
fn test_base58_system_program_id() {
    let data = [0u8; 32];
    let encoded = base58::encode(&data);
    assert_eq!(encoded, "11111111111111111111111111111111");
    let decoded = base58::decode(&encoded).unwrap();
    assert_eq!(decoded, data);
}

#[test]
fn test_base58_token_program_roundtrip() {
    let addr = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA";
    let decoded = base58::decode(addr).unwrap();
    assert_eq!(decoded.len(), 32);
    let reencoded = base58::encode(&decoded);
    assert_eq!(reencoded, addr);
}

#[test]
fn test_base58_leading_zeros() {
    let data = vec![0, 0, 0, 1, 2, 3];
    let encoded = base58::encode(&data);
    assert!(encoded.starts_with("111"));
    let decoded = base58::decode(&encoded).unwrap();
    assert_eq!(decoded, data);
}

#[test]
fn test_base58_invalid_chars() {
    assert!(base58::decode("0").is_err()); // '0' not in base58
    assert!(base58::decode("O").is_err()); // 'O' not in base58
    assert!(base58::decode("I").is_err()); // 'I' not in base58
    assert!(base58::decode("l").is_err()); // 'l' not in base58
}

// ─── CompactU16 ─────────────────────────────────────────────────────────

#[test]
fn test_compact_u16_known_vectors() {
    let vectors: Vec<(u16, Vec<u8>)> = vec![
        (0, vec![0x00]),
        (1, vec![0x01]),
        (127, vec![0x7F]),
        (128, vec![0x80, 0x01]),
        (255, vec![0xFF, 0x01]),
        (16383, vec![0xFF, 0x7F]),
        (16384, vec![0x80, 0x80, 0x01]),
        (65535, vec![0xFF, 0xFF, 0x03]),
    ];

    for (value, expected_bytes) in &vectors {
        let encoded = compact_u16::encode(*value);
        assert_eq!(
            &encoded, expected_bytes,
            "encode({}) failed",
            value
        );
        let (decoded, bytes_read) = compact_u16::decode(&encoded, 0).unwrap();
        assert_eq!(decoded, *value, "decode failed for {}", value);
        assert_eq!(bytes_read, encoded.len());
    }
}

#[test]
fn test_compact_u16_roundtrip_all_key_values() {
    for val in [0u16, 1, 127, 128, 255, 256, 16383, 16384, 32767, 65535] {
        let encoded = compact_u16::encode(val);
        let (decoded, _) = compact_u16::decode(&encoded, 0).unwrap();
        assert_eq!(decoded, val);
    }
}

#[test]
fn test_compact_u16_truncated_continuation() {
    // 0x80 alone has continuation bit set but no next byte
    assert!(compact_u16::decode(&[0x80], 0).is_err());
}

// ─── Ed25519 Signer ─────────────────────────────────────────────────────

#[test]
fn test_ed25519_sign_verify_roundtrip() {
    let seed = [0xABu8; 32];
    let signer = SoftwareSigner::from_seed(&seed).unwrap();
    let message = b"Hello Solana";
    let signature = signer.sign(message).unwrap();
    assert!(SoftwareSigner::verify(&signature, message, signer.public_key()));
}

#[test]
fn test_ed25519_wrong_message_fails() {
    let seed = [0xCDu8; 32];
    let signer = SoftwareSigner::from_seed(&seed).unwrap();
    let signature = signer.sign(b"correct").unwrap();
    assert!(!SoftwareSigner::verify(&signature, b"wrong", signer.public_key()));
}

#[test]
fn test_ed25519_signature_is_64_bytes() {
    let seed = [0x99u8; 32];
    let signer = SoftwareSigner::from_seed(&seed).unwrap();
    let signature = signer.sign(b"test").unwrap();
    assert_eq!(signature.len(), 64);
}

#[test]
fn test_ed25519_different_messages_different_sigs() {
    let seed = [0x42u8; 32];
    let signer = SoftwareSigner::from_seed(&seed).unwrap();
    let sig1 = signer.sign(b"message1").unwrap();
    let sig2 = signer.sign(b"message2").unwrap();
    assert_ne!(sig1, sig2);
}

#[test]
fn test_ed25519_cross_key_verify_fails() {
    let signer1 = SoftwareSigner::from_seed(&[0x11u8; 32]).unwrap();
    let signer2 = SoftwareSigner::from_seed(&[0x22u8; 32]).unwrap();
    let signature = signer1.sign(b"hello").unwrap();
    assert!(!SoftwareSigner::verify(&signature, b"hello", signer2.public_key()));
}

#[test]
fn test_ed25519_fee_payer_pubkey() {
    // From TransactionCompatTests: seed [0x01]*32 -> known pubkey
    let seed = [0x01u8; 32];
    let signer = SoftwareSigner::from_seed(&seed).unwrap();
    let expected_hex = "8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c";
    assert_eq!(hex::encode(signer.public_key().as_bytes()), expected_hex);
}

// ─── BIP39 Mnemonic ─────────────────────────────────────────────────────

#[test]
fn test_mnemonic_known_seed_derivation() {
    // BIP39 test vector: 16 bytes of 0x00 -> "abandon...about"
    let words: Vec<String> = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        .split_whitespace()
        .map(String::from)
        .collect();

    assert!(mnemonic::validate(&words));

    // BIP39 seed (PBKDF2-HMAC-SHA512)
    let seed = mnemonic::to_seed(&words, "").unwrap();
    let expected_seed_hex = "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4";
    assert_eq!(hex::encode(seed), expected_seed_hex);
}

#[test]
fn test_slip0010_solana_derivation() {
    let words: Vec<String> = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        .split_whitespace()
        .map(String::from)
        .collect();

    let (pubkey, private_key) = mnemonic::derive_keypair(&words, "").unwrap();

    // Expected from Swift MnemonicTests
    let expected_privkey_hex = "37df573b3ac4ad5b522e064e25b63ea16bcbe79d449e81a0268d1047948bb445";
    assert_eq!(hex::encode(private_key), expected_privkey_hex);

    let expected_address = "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk";
    assert_eq!(pubkey.to_base58(), expected_address);
}

// ─── Message Serialization ──────────────────────────────────────────────

#[test]
fn test_message_byte_layout() {
    // From MessageTests.swift: fee_payer=[0x01]*32, recipient=[0x02]*32, blockhash=[0xAA]*32
    let fee_payer = SolanaPublicKey::from_bytes(&[0x01u8; 32]).unwrap();
    let recipient = SolanaPublicKey::from_bytes(&[0x02u8; 32]).unwrap();

    // Use raw blockhash bytes [0xAA]*32 encoded as base58
    let blockhash_bytes = [0xAAu8; 32];
    let blockhash = base58::encode(&blockhash_bytes);

    let ix = system_program::transfer(&fee_payer, &recipient, 100);
    let message = Message::new(&fee_payer, &blockhash, &[ix]).unwrap();
    let serialized = message.serialize();

    // Header
    assert_eq!(serialized[0], 1, "numRequiredSignatures");
    assert_eq!(serialized[1], 0, "numReadonlySignedAccounts");
    assert_eq!(serialized[2], 1, "numReadonlyUnsignedAccounts");

    // Account count
    assert_eq!(serialized[3], 3, "account count (compact-u16)");

    // Fee payer is first
    assert_eq!(&serialized[4..36], &[0x01u8; 32]);

    // Recipient is second
    assert_eq!(&serialized[36..68], &[0x02u8; 32]);

    // System program (all zeros) is third
    assert_eq!(&serialized[68..100], &[0u8; 32]);

    // Blockhash
    assert_eq!(&serialized[100..132], &[0xAAu8; 32]);

    // Instruction count
    assert_eq!(serialized[132], 1);

    // Program ID index (System Program = index 2)
    assert_eq!(serialized[133], 2);

    // Account indices count
    assert_eq!(serialized[134], 2);

    // Account indices (from=0, to=1)
    assert_eq!(serialized[135], 0);
    assert_eq!(serialized[136], 1);

    // Data length
    assert_eq!(serialized[137], 12);

    // System Program transfer discriminator
    assert_eq!(serialized[138], 2);
}

// ─── Transaction Compatibility (byte-for-byte with web3.js) ─────────────

fn compat_fee_payer() -> (SoftwareSigner, SolanaPublicKey) {
    let seed = [0x01u8; 32];
    let signer = SoftwareSigner::from_seed(&seed).unwrap();
    let pubkey = signer.public_key().clone();
    (signer, pubkey)
}

fn compat_recipient() -> SolanaPublicKey {
    SolanaPublicKey::from_bytes(&[0x02u8; 32]).unwrap()
}

fn compat_blockhash() -> &'static str {
    "CVDFLCAjXhVWiPXH9nTCTpCgVzmDVoiPzNJYuccr1dqB"
}

#[test]
fn test_compat_simple_sol_transfer() {
    let (_signer, fee_payer) = compat_fee_payer();
    let recipient = compat_recipient();
    let blockhash = compat_blockhash();

    let ix = system_program::transfer(&fee_payer, &recipient, 1_000_000);
    let message = Message::new(&fee_payer, blockhash, &[ix]).unwrap();
    let serialized_msg = message.serialize();

    let expected_hex = "010001038a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c02020202020202020202020202020202020202020202020202020202020202020000000000000000000000000000000000000000000000000000000000000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa01020200010c0200000040420f0000000000";

    assert_eq!(hex::encode(&serialized_msg), expected_hex);
}

#[test]
fn test_compat_sol_transfer_with_compute_budget() {
    let (_signer, fee_payer) = compat_fee_payer();
    let recipient = compat_recipient();
    let blockhash = compat_blockhash();

    let ix_limit = compute_budget::set_compute_unit_limit(200_000);
    let ix_price = compute_budget::set_compute_unit_price(50_000);
    let ix_transfer = system_program::transfer(&fee_payer, &recipient, 1_000_000);

    let message = Message::new(&fee_payer, blockhash, &[ix_limit, ix_price, ix_transfer]).unwrap();
    let serialized_msg = message.serialize();

    let expected_hex = "010002048a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c020202020202020202020202020202020202020202020202020202020202020200000000000000000000000000000000000000000000000000000000000000000306466fe5211732ffecadba72c39be7bc8ce5bbc5f7126b2c439b3a40000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0303000502400d03000300090350c3000000000000020200010c0200000040420f0000000000";

    assert_eq!(hex::encode(&serialized_msg), expected_hex);
}

#[test]
fn test_compat_sol_transfer_with_jito_tip() {
    let (_signer, fee_payer) = compat_fee_payer();
    let recipient = compat_recipient();
    let blockhash = compat_blockhash();

    // Use the first Jito tip account deterministically
    let tip_account = SolanaPublicKey::from_base58(jito_tip::TIP_ACCOUNTS[0]).unwrap();

    let ix_limit = compute_budget::set_compute_unit_limit(200_000);
    let ix_price = compute_budget::set_compute_unit_price(50_000);
    let ix_transfer = system_program::transfer(&fee_payer, &recipient, 1_000_000);
    let ix_tip = system_program::transfer(&fee_payer, &tip_account, 840_000);

    let message = Message::new(
        &fee_payer,
        blockhash,
        &[ix_limit, ix_price, ix_transfer, ix_tip],
    )
    .unwrap();
    let serialized_msg = message.serialize();

    let expected_hex = "010002058a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c020202020202020202020202020202020202020202020202020202020202020278521cb179cebb8589b556a2d5ec94d2498682fdf9bb2af5ad64e491cc4153da00000000000000000000000000000000000000000000000000000000000000000306466fe5211732ffecadba72c39be7bc8ce5bbc5f7126b2c439b3a40000000aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0404000502400d03000400090350c3000000000000030200010c0200000040420f0000000000030200020c0200000040d10c0000000000";

    assert_eq!(hex::encode(&serialized_msg), expected_hex);
}

// ─── PDA Tests ──────────────────────────────────────────────────────────

#[test]
fn test_pda_known_ata() {
    // From PDATests.swift: known USDC ATA
    let owner = SolanaPublicKey::from_base58("7fUAJdStEuGbc3sM84cKRL6yYaaSstyLSU4ve21asR2r").unwrap();
    let mint = SolanaPublicKey::from_base58("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v").unwrap();

    let ata = token_program::associated_token_address(&owner, &mint).unwrap();
    assert_eq!(ata.to_base58(), "FEEHnCYLSjT7QZJvNoNiuFABCpAwvvZjZ4ak5dAaU636");
}

#[test]
fn test_pda_seed_too_long() {
    let program = SolanaPublicKey::from_bytes(&[0u8; 32]).unwrap();
    let long_seed = vec![0u8; 33];
    assert!(pda::create_program_address(&[&long_seed], &program).is_err());
}

// ─── System Program ─────────────────────────────────────────────────────

#[test]
fn test_system_program_transfer_data_layout() {
    let from = SolanaPublicKey::from_bytes(&[1u8; 32]).unwrap();
    let to = SolanaPublicKey::from_bytes(&[2u8; 32]).unwrap();
    let ix = system_program::transfer(&from, &to, 1_000_000);

    // 12 bytes: u32(2) + u64(lamports)
    assert_eq!(ix.data.len(), 12);
    assert_eq!(ix.data[0], 2); // Transfer discriminator
    assert_eq!(ix.data[1], 0);
    assert_eq!(ix.data[2], 0);
    assert_eq!(ix.data[3], 0);
    let lamports = u64::from_le_bytes(ix.data[4..12].try_into().unwrap());
    assert_eq!(lamports, 1_000_000);

    // Two accounts: from (signer+writable), to (writable)
    assert_eq!(ix.accounts.len(), 2);
    assert!(ix.accounts[0].is_signer);
    assert!(ix.accounts[0].is_writable);
    assert!(!ix.accounts[1].is_signer);
    assert!(ix.accounts[1].is_writable);
}

// ─── Token Program ──────────────────────────────────────────────────────

#[test]
fn test_token_transfer_data_layout() {
    let src = SolanaPublicKey::from_bytes(&[1u8; 32]).unwrap();
    let dst = SolanaPublicKey::from_bytes(&[2u8; 32]).unwrap();
    let owner = SolanaPublicKey::from_bytes(&[3u8; 32]).unwrap();
    let ix = token_program::transfer(&src, &dst, &owner, 500_000);

    assert_eq!(ix.data.len(), 9);
    assert_eq!(ix.data[0], 3); // SPL Transfer discriminator
    let amount = u64::from_le_bytes(ix.data[1..9].try_into().unwrap());
    assert_eq!(amount, 500_000);
}

// ─── Transaction Sign + Serialize ───────────────────────────────────────

#[test]
fn test_signed_transaction_not_all_zeros() {
    let (signer, fee_payer) = compat_fee_payer();
    let recipient = compat_recipient();

    let ix = system_program::transfer(&fee_payer, &recipient, 42);
    let message = Message::new(&fee_payer, compat_blockhash(), &[ix]).unwrap();
    let mut tx = Transaction::new(message);
    tx.sign(&signer).unwrap();

    assert_ne!(tx.signatures[0], [0u8; 64]);

    // Verify the signature is valid
    let message_bytes = tx.message.serialize();
    assert!(SoftwareSigner::verify(&tx.signatures[0], &message_bytes, &fee_payer));
}
