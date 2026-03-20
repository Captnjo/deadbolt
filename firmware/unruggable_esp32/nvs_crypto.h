// AES-256-CBC encryption/decryption for NVS seed storage.
//
// Encryption key is derived from the device MAC address using HMAC-SHA256
// with a fixed salt ("deadbolt-nvs-v1"), providing device-specific encryption
// without requiring a user-supplied key.
//
// NVS storage format: IV[16] || AES-256-CBC-ciphertext[48] = 64 bytes total
// Private key is PKCS7-padded from 32 bytes to 48 bytes (pad byte = 0x10).
//
// Security note: key derivation from MAC address deters casual NVS readout
// but does not protect against a determined adversary with flash dump access.
// This is acceptable for v1 given the single-device use case and the fact that
// the mnemonic (required for full recovery) is never stored on-device.

#ifndef NVS_CRYPTO_H
#define NVS_CRYPTO_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

// NVS encrypted blob size: 16-byte IV + 48-byte ciphertext
#define NVS_ENC_SIZE 64

// -------------------------------------------------------------------
// AES key derivation from device MAC
// -------------------------------------------------------------------

// deriveEncKey(keyOut32)
//   Derives a 32-byte AES-256 key from the device's factory-programmed
//   MAC address using HMAC-SHA256.
//
//   Algorithm:
//     mac[6]  = esp_efuse_mac_get_default()
//     key[32] = HMAC-SHA256(key=mac[6], data="deadbolt-nvs-v1")
//
//   Output: keyOut32[32] — AES-256 key (caller must zeroize after use)
void deriveEncKey(uint8_t keyOut32[32]);

// -------------------------------------------------------------------
// NVS encryption / decryption
// -------------------------------------------------------------------

// encryptSeed(privkey32, outBuf, outLen)
//   AES-256-CBC encrypts a 32-byte private key for NVS storage.
//
//   Process:
//     1. Derive AES key via deriveEncKey()
//     2. Generate random 16-byte IV via esp_fill_random()
//     3. PKCS7-pad privkey32 to 48 bytes (pad byte = 0x10)
//     4. AES-256-CBC encrypt to 48-byte ciphertext
//     5. Output: IV[16] || ciphertext[48] = 64 bytes
//
//   Returns: true on success, false on mbedtls error
//   Output:  outBuf[NVS_ENC_SIZE], *outLen = NVS_ENC_SIZE
bool encryptSeed(const uint8_t* privkey32, uint8_t* outBuf, size_t* outLen);

// decryptSeed(encData, encLen, privkeyOut32)
//   AES-256-CBC decrypts an NVS blob back to a 32-byte private key.
//
//   Process:
//     1. Validate encLen == NVS_ENC_SIZE (64)
//     2. Extract IV = encData[0..16], ciphertext = encData[16..64]
//     3. Derive AES key via deriveEncKey()
//     4. AES-256-CBC decrypt to 48-byte plaintext
//     5. Verify PKCS7 padding (last 16 bytes should all be 0x10)
//     6. Copy first 32 bytes to privkeyOut32
//
//   Returns: true on success, false if encLen is wrong or padding is invalid
bool decryptSeed(const uint8_t* encData, size_t encLen, uint8_t* privkeyOut32);

#endif // NVS_CRYPTO_H
