// AES-256-CBC encryption/decryption for NVS seed storage.
// See nvs_crypto.h for full documentation.

#include "nvs_crypto.h"

#include <string.h>
#include "esp_system.h"

// MAC address via eFuse
#include "esp_mac.h"

// mbedtls for AES and HMAC
#include "mbedtls/aes.h"
#include "mbedtls/md.h"

// -------------------------------------------------------------------
// AES key derivation from device MAC
// -------------------------------------------------------------------

void deriveEncKey(uint8_t keyOut32[32]) {
  uint8_t mac[6];
  esp_efuse_mac_get_default(mac);

  // HMAC-SHA256(key=mac[6], data="deadbolt-nvs-v1")
  // The MAC is the HMAC key; the fixed salt is the data.
  // This binds the AES key to the physical device.
  const char* salt = "deadbolt-nvs-v1";
  mbedtls_md_hmac(
    mbedtls_md_info_from_type(MBEDTLS_MD_SHA256),
    mac, 6,
    (const uint8_t*)salt, strlen(salt),
    keyOut32
  );

  // Zeroize MAC — no longer needed
  memset(mac, 0, sizeof(mac));
}

// -------------------------------------------------------------------
// NVS encryption
// -------------------------------------------------------------------

bool encryptSeed(const uint8_t* privkey32, uint8_t* outBuf, size_t* outLen) {
  uint8_t encKey[32];
  deriveEncKey(encKey);

  // Generate random 16-byte IV
  uint8_t iv[16];
  esp_fill_random(iv, sizeof(iv));

  // PKCS7-pad the 32-byte private key to 48 bytes.
  // Pad byte = 0x10 (16 decimal, since we're padding 16 bytes).
  // This is standard PKCS7 for AES-CBC.
  uint8_t padded[48];
  memcpy(padded, privkey32, 32);
  memset(padded + 32, 16, 16); // 16 pad bytes, each with value 0x10

  // AES-256-CBC encryption
  mbedtls_aes_context aes;
  mbedtls_aes_init(&aes);

  int ret = mbedtls_aes_setkey_enc(&aes, encKey, 256);
  if (ret != 0) {
    mbedtls_aes_free(&aes);
    memset(encKey, 0, sizeof(encKey));
    memset(padded, 0, sizeof(padded));
    return false;
  }

  // Ciphertext occupies outBuf[16..64]; IV is placed at outBuf[0..16]
  uint8_t ciphertext[48];
  uint8_t iv_copy[16];
  memcpy(iv_copy, iv, 16); // mbedtls_aes_crypt_cbc modifies the IV in place

  ret = mbedtls_aes_crypt_cbc(&aes, MBEDTLS_AES_ENCRYPT, 48, iv_copy, padded, ciphertext);
  mbedtls_aes_free(&aes);

  if (ret != 0) {
    memset(encKey, 0, sizeof(encKey));
    memset(padded, 0, sizeof(padded));
    return false;
  }

  // Assemble output: IV[16] || ciphertext[48]
  memcpy(outBuf,      iv,         16);
  memcpy(outBuf + 16, ciphertext, 48);
  *outLen = NVS_ENC_SIZE;

  // Zeroize sensitive intermediates
  memset(encKey,     0, sizeof(encKey));
  memset(padded,     0, sizeof(padded));
  memset(ciphertext, 0, sizeof(ciphertext));
  memset(iv,         0, sizeof(iv));
  memset(iv_copy,    0, sizeof(iv_copy));

  return true;
}

// -------------------------------------------------------------------
// NVS decryption
// -------------------------------------------------------------------

bool decryptSeed(const uint8_t* encData, size_t encLen, uint8_t* privkeyOut32) {
  if (encLen != NVS_ENC_SIZE) {
    return false;
  }

  // Extract IV (first 16 bytes) and ciphertext (remaining 48 bytes)
  uint8_t iv[16];
  uint8_t ciphertext[48];
  memcpy(iv,         encData,      16);
  memcpy(ciphertext, encData + 16, 48);

  uint8_t encKey[32];
  deriveEncKey(encKey);

  // AES-256-CBC decryption
  mbedtls_aes_context aes;
  mbedtls_aes_init(&aes);

  int ret = mbedtls_aes_setkey_dec(&aes, encKey, 256);
  if (ret != 0) {
    mbedtls_aes_free(&aes);
    memset(encKey, 0, sizeof(encKey));
    return false;
  }

  uint8_t plaintext[48];
  ret = mbedtls_aes_crypt_cbc(&aes, MBEDTLS_AES_DECRYPT, 48, iv, ciphertext, plaintext);
  mbedtls_aes_free(&aes);

  if (ret != 0) {
    memset(encKey,    0, sizeof(encKey));
    memset(plaintext, 0, sizeof(plaintext));
    return false;
  }

  // Verify PKCS7 padding: last 16 bytes should all be 0x10
  bool padOk = true;
  for (int i = 32; i < 48; i++) {
    if (plaintext[i] != 0x10) {
      padOk = false;
      break;
    }
  }

  if (!padOk) {
    memset(encKey,    0, sizeof(encKey));
    memset(plaintext, 0, sizeof(plaintext));
    return false;
  }

  // Copy private key (first 32 bytes)
  memcpy(privkeyOut32, plaintext, 32);

  // Zeroize all sensitive intermediates
  memset(encKey,    0, sizeof(encKey));
  memset(plaintext, 0, sizeof(plaintext));
  memset(iv,        0, sizeof(iv));
  memset(ciphertext, 0, sizeof(ciphertext));

  return true;
}
