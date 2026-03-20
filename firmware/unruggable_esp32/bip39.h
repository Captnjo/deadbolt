// BIP39 mnemonic generation, PBKDF2 seed derivation, and SLIP-0010 Ed25519 key derivation
// for ESP32 (Arduino framework).
//
// Algorithm reference: rust/deadbolt_core/src/crypto/mnemonic.rs
// The C implementations are algorithm-for-algorithm ports of that Rust code.

#ifndef BIP39_H
#define BIP39_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

// Maximum word length in BIP39 English wordlist is 8 characters; use 10 for safety.
#define BIP39_WORD_MAXLEN 10
#define BIP39_WORD_COUNT  12

// -------------------------------------------------------------------
// Entropy validation
// -------------------------------------------------------------------

// validateEntropy()
//   Samples 256 bytes of hardware entropy from esp_fill_random()
//   (with bootloader_random_enable/disable bracketing) and runs a
//   chi-squared uniformity test (255 DOF, p=0.001 threshold = 350.0).
//
//   Returns: true  if entropy passes the chi-squared test (< 350.0)
//            false if entropy fails (hardware RNG may be compromised)
bool validateEntropy();

// -------------------------------------------------------------------
// BIP39 mnemonic generation
// -------------------------------------------------------------------

// generateMnemonic(words)
//   Generates a valid 12-word BIP39 mnemonic from verified hardware entropy.
//
//   Algorithm (matches mnemonic.rs generate(12)):
//     1. 128-bit entropy via esp_fill_random
//     2. SHA-256 checksum: top 4 bits of hash[0]
//     3. 132-bit stream -> 12 x 11-bit indices -> BIP39 wordlist lookup
//
//   Output: words[12][BIP39_WORD_MAXLEN] filled with BIP39 words.
//   Entropy buffer is zeroized after use.
void generateMnemonic(char words[BIP39_WORD_COUNT][BIP39_WORD_MAXLEN]);

// -------------------------------------------------------------------
// BIP39 seed derivation (PBKDF2-HMAC-SHA512)
// -------------------------------------------------------------------

// mnemonicToSeed(mnemonicStr, seed)
//   Derives a 64-byte BIP39 seed from a mnemonic string using
//   PBKDF2-HMAC-SHA512 with salt="mnemonic", 2048 iterations.
//
//   Matches mnemonic.rs to_seed(words, "") — no custom passphrase for v1.
//
//   Input:  mnemonicStr — 12 words joined by single spaces (null-terminated)
//   Output: seed[64]   — PBKDF2 output (BIP39 seed)
void mnemonicToSeed(const char* mnemonicStr, uint8_t seed[64]);

// -------------------------------------------------------------------
// SLIP-0010 Ed25519 key derivation
// -------------------------------------------------------------------

// slip10Derive(bip39seed64, privkeyOut32)
//   Derives an Ed25519 private key from a BIP39 seed using SLIP-0010
//   at the Solana derivation path m/44'/501'/0'/0'.
//
//   Algorithm (matches mnemonic.rs derive_keypair()):
//     1. Master key: HMAC-SHA512(key="ed25519 seed", data=bip39seed64)
//     2. 4 hardened child derivations at path {44, 501, 0, 0}
//        - hardened index = component + 0x80000000
//        - data[37] = 0x00 || key[32] || big-endian(hIndex)[4]
//        - I = HMAC-SHA512(key=chain, data=data)
//        - key = I[0..32], chain = I[32..64]
//     3. Final key[32] is the Ed25519 private key seed
//
//   Input:  bip39seed64[64] — BIP39 seed from mnemonicToSeed()
//   Output: privkeyOut32[32] — Ed25519 private key seed
//   Note:   key, chain, and bip39seed64 are zeroized after use.
void slip10Derive(const uint8_t* bip39seed64, uint8_t privkeyOut32[32]);

#endif // BIP39_H
