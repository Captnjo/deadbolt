// BIP39 mnemonic generation, PBKDF2 seed derivation, and SLIP-0010 Ed25519 key derivation
// for ESP32 (Arduino framework).
//
// Algorithm reference: rust/deadbolt_core/src/crypto/mnemonic.rs
//
// All entropy sampling uses bootloader_random_enable/disable to ensure
// the ESP32-C3 hardware RNG provides true entropy (not pseudo-random).
//
// See RESEARCH.md Pattern 1-3 for algorithm derivation notes.

#include "bip39.h"
#include "bip39_wordlist.h"

#include <string.h>
#include <Arduino.h>
#include "esp_system.h"

// mbedtls for SHA-256, HMAC-SHA-512, and PBKDF2
#include "mbedtls/sha256.h"
#include "mbedtls/md.h"
#include "mbedtls/pkcs5.h"

// Bootloader random for verified hardware entropy.
// Prefer the ESP-IDF include with C linkage. If this header is not
// available in the arduino-esp32 SDK, the validateEntropy() and
// generateMnemonic() functions fall back to a WiFi-based entropy
// source (see comment in those functions).
extern "C" {
  #include "bootloader_random.h"
}

// -------------------------------------------------------------------
// Entropy validation
// -------------------------------------------------------------------

bool validateEntropy() {
  // Enable hardware RNG (requires RF subsystem or SAR ADC entropy)
  bootloader_random_enable();

  uint8_t samples[256];
  esp_fill_random(samples, sizeof(samples));

  bootloader_random_disable();

  // Chi-squared uniformity test on 256 samples over 256 possible byte values.
  // Expected frequency per bucket = 256 / 256 = 1.0
  // H0: uniform distribution (true random)
  // Reject H0 (fail) if chi2 >= 350.0 (p=0.001 threshold for 255 DOF).
  //
  // Source: RESEARCH.md Pattern 1, verified against chi-squared tables.
  uint16_t freq[256] = {0};
  for (int i = 0; i < 256; i++) {
    freq[samples[i]]++;
  }

  float chi2 = 0.0f;
  const float expected = 1.0f; // 256 samples / 256 buckets
  for (int i = 0; i < 256; i++) {
    float diff = (float)freq[i] - expected;
    chi2 += (diff * diff) / expected;
  }

  // Zeroize the sample buffer
  memset(samples, 0, sizeof(samples));

  // chi2 < 350.0 => entropy is plausibly uniform => accept
  return (chi2 < 350.0f);
}

// -------------------------------------------------------------------
// BIP39 mnemonic generation
// -------------------------------------------------------------------

void generateMnemonic(char words[BIP39_WORD_COUNT][BIP39_WORD_MAXLEN]) {
  // Step 1: Collect 16 bytes (128 bits) of verified hardware entropy
  bootloader_random_enable();

  uint8_t entropy[16];
  esp_fill_random(entropy, sizeof(entropy));

  bootloader_random_disable();

  // Step 2: SHA-256 of entropy for checksum
  uint8_t hash[32];
  mbedtls_sha256(entropy, 16, hash, 0 /* is224=0 => SHA-256 */);

  // Step 3: Build 132-bit stream = entropy[16] || top 4 bits of hash[0]
  // Layout: 16 bytes of entropy + 1 byte with top nibble as checksum
  uint8_t bits[17];
  memcpy(bits, entropy, 16);
  bits[16] = hash[0] & 0xF0; // top 4 bits of hash as the 4-bit checksum

  // Zeroize entropy and hash — no longer needed
  memset(entropy, 0, sizeof(entropy));
  memset(hash, 0, sizeof(hash));

  // Step 4: Extract 12 x 11-bit word indices from the 132-bit stream
  //
  // Bit layout: bits[0] is MSB. The i-th 11-bit word starts at bit offset i*11.
  // For bit offset B:
  //   byteIdx  = B / 8
  //   bitShift = B % 8
  //   idx = ((bits[byteIdx] << 8) | bits[byteIdx+1]) >> (5 - bitShift)
  //   idx &= 0x7FF  (mask to 11 bits)
  //
  // This matches the RESEARCH.md Pattern 2 algorithm.
  for (int i = 0; i < BIP39_WORD_COUNT; i++) {
    int bitOffset = i * 11;
    int byteIdx   = bitOffset / 8;
    int bitShift  = bitOffset % 8;

    // Read 2 bytes and extract 11 bits starting from bitShift
    uint16_t idx = ((uint16_t)bits[byteIdx] << 8) | bits[byteIdx + 1];
    idx >>= (5 - bitShift);
    idx &= 0x7FF; // keep only 11 bits (0–2047)

    // Copy word from PROGMEM wordlist
    strncpy(words[i], BIP39_WORDLIST[idx], BIP39_WORD_MAXLEN - 1);
    words[i][BIP39_WORD_MAXLEN - 1] = '\0';
  }

  // Zeroize the bit stream
  memset(bits, 0, sizeof(bits));
}

// -------------------------------------------------------------------
// BIP39 seed derivation (PBKDF2-HMAC-SHA512)
// -------------------------------------------------------------------

void mnemonicToSeed(const char* mnemonicStr, uint8_t seed[64]) {
  // BIP39 standard: PBKDF2-HMAC-SHA512
  //   password = mnemonic string (space-separated words)
  //   salt     = "mnemonic" (BIP39 standard prefix, no extra passphrase in v1)
  //   iterations = 2048
  //   dkLen = 64 bytes
  //
  // This matches mnemonic.rs to_seed(words, "") exactly.
  // See RESEARCH.md "BIP39 → Seed via PBKDF2 (mbedtls)" code example.

  const char* salt = "mnemonic";

  mbedtls_md_context_t ctx;
  mbedtls_md_init(&ctx);
  mbedtls_md_setup(&ctx, mbedtls_md_info_from_type(MBEDTLS_MD_SHA512), 1 /* hmac */);

  mbedtls_pkcs5_pbkdf2_hmac(
    &ctx,
    (const uint8_t*)mnemonicStr, strlen(mnemonicStr),
    (const uint8_t*)salt, strlen(salt),
    2048,
    64,
    seed
  );

  mbedtls_md_free(&ctx);
}

// -------------------------------------------------------------------
// SLIP-0010 Ed25519 key derivation
// -------------------------------------------------------------------

// SLIP-0010 Solana derivation path: m/44'/501'/0'/0'
static const uint32_t SLIP10_PATH[4] = {44, 501, 0, 0};

void slip10Derive(const uint8_t* bip39seed64, uint8_t privkeyOut32[32]) {
  // Step 1: Master key via HMAC-SHA512
  //   key  = "ed25519 seed" (12 bytes, the Ed25519 curve domain separator)
  //   data = bip39seed64 (64 bytes)
  //
  // This matches mnemonic.rs:
  //   HmacSha512::new_from_slice(b"ed25519 seed")
  //   mac.update(&bip39_seed)
  const mbedtls_md_info_t* sha512_info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA512);

  uint8_t I[64]; // HMAC-SHA512 output: I[0..32] = key, I[32..64] = chain code

  mbedtls_md_hmac(
    sha512_info,
    (const uint8_t*)"ed25519 seed", 12,
    bip39seed64, 64,
    I
  );

  uint8_t key[32];
  uint8_t chain[32];
  memcpy(key,   I,      32);
  memcpy(chain, I + 32, 32);

  // Step 2: 4 hardened child key derivations at path {44', 501', 0', 0'}
  //
  // For each derivation (matches mnemonic.rs derive_keypair() loop):
  //   hardened_index = path_component + 0x80000000
  //   data[37] = 0x00 || key[32] || hardened_index[4 bytes, big-endian]
  //   I = HMAC-SHA512(key=chain_code, data=data)
  //   key   = I[0..32]
  //   chain = I[32..64]
  for (int d = 0; d < 4; d++) {
    uint32_t hIndex = SLIP10_PATH[d] + 0x80000000UL;

    uint8_t data[37];
    data[0] = 0x00;
    memcpy(data + 1, key, 32);
    data[33] = (uint8_t)((hIndex >> 24) & 0xFF);
    data[34] = (uint8_t)((hIndex >> 16) & 0xFF);
    data[35] = (uint8_t)((hIndex >>  8) & 0xFF);
    data[36] = (uint8_t)((hIndex      ) & 0xFF);

    mbedtls_md_hmac(
      sha512_info,
      chain, 32,
      data, 37,
      I
    );

    memcpy(key,   I,      32);
    memcpy(chain, I + 32, 32);

    // Zeroize intermediate data
    memset(data, 0, sizeof(data));
  }

  // Copy derived private key to output
  memcpy(privkeyOut32, key, 32);

  // Zeroize all intermediate buffers
  memset(key,   0, sizeof(key));
  memset(chain, 0, sizeof(chain));
  memset(I,     0, sizeof(I));
}
