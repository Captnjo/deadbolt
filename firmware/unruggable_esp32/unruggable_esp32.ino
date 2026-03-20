// Unruggable ESP32 - Phase 5: BIP39 Hardware Wallet
// Board: ESP32-C3 SuperMini
//
// Serial protocol (JSON lines):
//   Commands:  {"cmd":"ping"} | {"cmd":"pubkey"} | {"cmd":"generate"} |
//              {"cmd":"sign","payload":"hex..."} | {"cmd":"reset"} |
//              {"cmd":"entropy_check"}
//   Responses: {"status":"ok|error|pending|signed|generating", ...}
//
// Key lifecycle:
//   - generate command: validateEntropy -> generateMnemonic -> mnemonicToSeed ->
//     slip10Derive -> Ed25519 pubkey -> encryptSeed -> NVS store
//   - Boot: loadKeypair from encrypted NVS (migration path for old plaintext keys)
//   - reset command: nvs_flash_erase + esp_restart (full partition wipe)

#include <Preferences.h>
#include <Ed25519.h>

#include "bip39.h"
#include "nvs_crypto.h"

// NVS flash erase requires C linkage
extern "C" {
  #include "nvs_flash.h"
}

#define LED_PIN 8
#define BOOT_BTN 9
#define SIGN_TIMEOUT_MS   30000  // 30 seconds to confirm signing
#define SERIAL_BUF_SIZE   4096   // max incoming message size

Preferences prefs;

uint8_t privateKey[32];
uint8_t publicKey[32];
char solanaAddress[45];

bool hasKey = false;

// Serial protocol buffer
char serialBuf[SERIAL_BUF_SIZE];
int serialBufIdx = 0;

// Signing state machine
enum State { IDLE, AWAITING_CONFIRM };
State state = IDLE;
uint8_t pendingMessage[1232]; // max Solana tx message size
size_t pendingMessageLen = 0;
unsigned long signRequestTime = 0;

// ---- Base58 encoder ----
static const char B58_ALPHA[] = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

void base58Encode(const uint8_t *input, size_t inputLen, char *output, size_t *outputLen) {
  size_t zeros = 0;
  while (zeros < inputLen && input[zeros] == 0) zeros++;
  size_t size = inputLen * 2;
  uint8_t *buf = (uint8_t *)calloc(size, 1);
  for (size_t i = zeros; i < inputLen; i++) {
    int carry = input[i];
    for (size_t j = size; j-- > 0;) {
      carry += 256 * buf[j];
      buf[j] = carry % 58;
      carry /= 58;
    }
  }
  size_t it = 0;
  while (it < size && buf[it] == 0) it++;
  size_t idx = 0;
  for (size_t i = 0; i < zeros; i++) output[idx++] = '1';
  for (; it < size; it++) output[idx++] = B58_ALPHA[buf[it]];
  output[idx] = '\0';
  *outputLen = idx;
  free(buf);
}

// ---- Hex utilities ----
uint8_t hexCharToNibble(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return 0;
}

size_t hexDecode(const char *hex, size_t hexLen, uint8_t *out, size_t outMax) {
  size_t bytes = hexLen / 2;
  if (bytes > outMax) bytes = outMax;
  for (size_t i = 0; i < bytes; i++) {
    out[i] = (hexCharToNibble(hex[i * 2]) << 4) | hexCharToNibble(hex[i * 2 + 1]);
  }
  return bytes;
}

void hexEncode(const uint8_t *data, size_t len, char *out) {
  static const char hexchars[] = "0123456789abcdef";
  for (size_t i = 0; i < len; i++) {
    out[i * 2]     = hexchars[(data[i] >> 4) & 0x0F];
    out[i * 2 + 1] = hexchars[data[i] & 0x0F];
  }
  out[len * 2] = '\0';
}

// ---- LED helpers ----
void ledSolid(bool on) { digitalWrite(LED_PIN, on ? LOW : HIGH); }

void ledBlink(int times, int ms) {
  for (int i = 0; i < times; i++) {
    digitalWrite(LED_PIN, LOW); delay(ms);
    digitalWrite(LED_PIN, HIGH); delay(ms);
  }
}

// LED patterns:
// - Entropy failure:         10 rapid blinks at 50ms
// - Generation in progress:  slow pulse 500ms on/off (in loop)
// - Generation complete:     3 blinks at 200ms then solid on
// - Factory reset pending:   very fast blink 30ms (in loop)
// - Awaiting sign confirm:   slow pulse 300ms (existing)

void ledEntropyError() {
  for (int i = 0; i < 10; i++) {
    digitalWrite(LED_PIN, LOW); delay(50);
    digitalWrite(LED_PIN, HIGH); delay(50);
  }
}

void ledGenerateComplete() {
  ledBlink(3, 200);
  ledSolid(true);
}

// ---- Key management ----

// generateBip39Keypair()
//   Full BIP39 keypair generation: entropy validate -> mnemonic -> seed ->
//   SLIP-0010 derive -> Ed25519 pubkey -> AES-256-CBC encrypt -> NVS store.
//
//   Returns true on success, false on entropy failure or encryption error.
//   On success, publicKey, privateKey, solanaAddress, and hasKey are updated.
bool generateBip39Keypair(char words[BIP39_WORD_COUNT][BIP39_WORD_MAXLEN]) {
  // Step 1: Validate entropy before generating keys
  if (!validateEntropy()) {
    ledEntropyError();
    return false;
  }

  // Step 2: Generate 12-word BIP39 mnemonic
  generateMnemonic(words);

  // Step 3: Build mnemonic string (words joined by spaces)
  char mnemonicStr[BIP39_WORD_COUNT * (BIP39_WORD_MAXLEN + 1) + 1];
  mnemonicStr[0] = '\0';
  for (int i = 0; i < BIP39_WORD_COUNT; i++) {
    if (i > 0) strcat(mnemonicStr, " ");
    strcat(mnemonicStr, words[i]);
  }

  // Step 4: PBKDF2-HMAC-SHA512 to get 64-byte BIP39 seed
  uint8_t bip39Seed[64];
  mnemonicToSeed(mnemonicStr, bip39Seed);

  // Zeroize mnemonic string immediately after seed derivation
  memset(mnemonicStr, 0, sizeof(mnemonicStr));

  // Step 5: SLIP-0010 derivation -> 32-byte Ed25519 private key
  slip10Derive(bip39Seed, privateKey);

  // Zeroize BIP39 seed — private key is now in privateKey[32]
  memset(bip39Seed, 0, sizeof(bip39Seed));

  // Step 6: Derive Ed25519 public key from private key
  Ed25519::derivePublicKey(publicKey, privateKey);

  // Step 7: Base58-encode public key to Solana address
  size_t addrLen;
  base58Encode(publicKey, 32, solanaAddress, &addrLen);

  // Step 8: Encrypt private key for NVS storage
  uint8_t encBuf[NVS_ENC_SIZE];
  size_t encLen = 0;
  if (!encryptSeed(privateKey, encBuf, &encLen)) {
    sendError("encrypt_failed");
    return false;
  }

  // Step 9: Store encrypted key and pubkey in NVS
  prefs.begin("unruggable", false);
  prefs.putBytes("enc_privkey", encBuf, encLen);
  prefs.putBytes("pubkey", publicKey, 32);
  prefs.end();

  // Zeroize encryption buffer
  memset(encBuf, 0, sizeof(encBuf));

  hasKey = true;
  return true;
}

// loadKeypair()
//   Loads the keypair from NVS. Reads enc_privkey (AES-256-CBC encrypted).
//   Migration path: if old plaintext "privkey" key exists, re-encrypts to
//   "enc_privkey" and removes the old entry.
//
//   Returns true if a valid keypair was loaded.
bool loadKeypair() {
  prefs.begin("unruggable", false); // read-write for potential migration

  // Check for new encrypted format first
  size_t encLen = prefs.getBytesLength("enc_privkey");
  if (encLen == NVS_ENC_SIZE) {
    uint8_t encBuf[NVS_ENC_SIZE];
    prefs.getBytes("enc_privkey", encBuf, NVS_ENC_SIZE);

    size_t pubLen = prefs.getBytes("pubkey", publicKey, 32);

    if (pubLen == 32) {
      bool ok = decryptSeed(encBuf, NVS_ENC_SIZE, privateKey);
      memset(encBuf, 0, sizeof(encBuf));

      if (ok) {
        size_t addrLen;
        base58Encode(publicKey, 32, solanaAddress, &addrLen);
        hasKey = true;
        prefs.end();
        return true;
      }
    }
  }

  // Migration path: old plaintext "privkey" exists (pre-BIP39 firmware)
  size_t oldPrivLen = prefs.getBytesLength("privkey");
  if (oldPrivLen == 32) {
    uint8_t oldPrivkey[32];
    prefs.getBytes("privkey", oldPrivkey, 32);
    size_t pubLen = prefs.getBytes("pubkey", publicKey, 32);

    if (pubLen == 32) {
      // Re-encrypt the old plaintext key to new format
      uint8_t encBuf[NVS_ENC_SIZE];
      size_t encLen2 = 0;
      if (encryptSeed(oldPrivkey, encBuf, &encLen2)) {
        prefs.putBytes("enc_privkey", encBuf, encLen2);
        prefs.remove("privkey"); // remove the old plaintext key
        memset(encBuf, 0, sizeof(encBuf));
      }

      memcpy(privateKey, oldPrivkey, 32);
      memset(oldPrivkey, 0, sizeof(oldPrivkey));

      size_t addrLen;
      base58Encode(publicKey, 32, solanaAddress, &addrLen);
      hasKey = true;
      prefs.end();
      return true;
    }
    memset(oldPrivkey, 0, sizeof(oldPrivkey));
  }

  prefs.end();
  return false;
}

// ---- JSON response helpers ----
void sendResponse(const char *status, const char *key1, const char *val1,
                  const char *key2 = nullptr, const char *val2 = nullptr) {
  Serial.print("{\"status\":\"");
  Serial.print(status);
  Serial.print("\",\"");
  Serial.print(key1);
  Serial.print("\":\"");
  Serial.print(val1);
  Serial.print("\"");
  if (key2 && val2) {
    Serial.print(",\"");
    Serial.print(key2);
    Serial.print("\":\"");
    Serial.print(val2);
    Serial.print("\"");
  }
  Serial.println("}");
}

void sendError(const char *msg) {
  sendResponse("error", "msg", msg);
}

// ---- Command handlers ----

void handleGetPubkey() {
  if (!hasKey) { sendError("no_key"); return; }
  char hexPub[65];
  hexEncode(publicKey, 32, hexPub);
  sendResponse("ok", "pubkey", hexPub, "address", solanaAddress);
}

void handleSign(const char *hexPayload, size_t hexLen) {
  if (!hasKey) { sendError("no_key"); return; }
  if (state == AWAITING_CONFIRM) { sendError("busy"); return; }

  pendingMessageLen = hexDecode(hexPayload, hexLen, pendingMessage, sizeof(pendingMessage));
  if (pendingMessageLen == 0) { sendError("bad_payload"); return; }

  state = AWAITING_CONFIRM;
  signRequestTime = millis();

  Serial.print("{\"status\":\"pending\",\"msg\":\"Confirm on device\",\"bytes\":");
  Serial.print(pendingMessageLen);
  Serial.println("}");

  ledBlink(5, 80);
  ledSolid(true);
}

// handleGenerateBip39()
//   Initiates BIP39 keypair generation with mandatory 5-second BOOT button hold.
//   Returns 12 mnemonic words in the JSON response on success.
void handleGenerateBip39() {
  // Immediately notify host that we are waiting for physical confirmation
  Serial.println("{\"status\":\"generating\",\"msg\":\"Hold BOOT button for 5 seconds to confirm\"}");

  // Wait for BOOT button held for 5 seconds
  // LED solid while waiting for button
  ledSolid(true);

  unsigned long btnDownTime = 0;
  bool btnWasDown = false;
  const unsigned long HOLD_REQUIRED = 5000;
  const unsigned long WAIT_TIMEOUT  = 60000; // 60s to start holding
  unsigned long waitStart = millis();

  while (true) {
    bool btnDown = (digitalRead(BOOT_BTN) == LOW);

    if (btnDown && !btnWasDown) {
      // Button just pressed — start timing
      btnDownTime = millis();
    }

    if (btnDown) {
      unsigned long heldFor = millis() - btnDownTime;
      if (heldFor >= HOLD_REQUIRED) {
        // Button held for 5 seconds — proceed with generation
        break;
      }
    } else if (!btnDown && btnWasDown) {
      // Button released before 5 seconds — cancelled
      sendError("generation_cancelled");
      ledSolid(false);
      return;
    }

    // Timeout: user never started pressing
    if (!btnDown && (millis() - waitStart > WAIT_TIMEOUT)) {
      sendError("generation_cancelled");
      ledSolid(false);
      return;
    }

    btnWasDown = btnDown;

    // Slow pulse LED while waiting for button
    static unsigned long lastPulse = 0;
    static bool pulseState = false;
    if (millis() - lastPulse > 500) {
      lastPulse = millis();
      pulseState = !pulseState;
      ledSolid(pulseState);
    }

    delay(10);
  }

  // Generation begins — LED fast pulse indicates work in progress
  ledSolid(false);

  char words[BIP39_WORD_COUNT][BIP39_WORD_MAXLEN];
  memset(words, 0, sizeof(words));

  if (!generateBip39Keypair(words)) {
    // generateBip39Keypair already sent an error or lit the entropy-error LED
    sendError("entropy_check_failed");
    memset(words, 0, sizeof(words));
    ledSolid(true);
    return;
  }

  // Build hex-encoded pubkey
  char hexPub[65];
  hexEncode(publicKey, 32, hexPub);

  // Send JSON response with words array
  // Built manually to avoid JSON library dependency
  Serial.print("{\"status\":\"ok\",\"words\":[");
  for (int i = 0; i < BIP39_WORD_COUNT; i++) {
    Serial.print("\"");
    Serial.print(words[i]);
    Serial.print("\"");
    if (i < BIP39_WORD_COUNT - 1) Serial.print(",");
  }
  Serial.print("],\"pubkey\":\"");
  Serial.print(hexPub);
  Serial.print("\",\"address\":\"");
  Serial.print(solanaAddress);
  Serial.println("\"}");

  // Zeroize the words from the stack immediately after sending
  memset(words, 0, sizeof(words));

  ledGenerateComplete();
}

// handleFactoryReset()
//   Erases the entire NVS partition after 5-second BOOT button hold.
//   Device reboots after successful erase.
void handleFactoryReset() {
  Serial.println("{\"status\":\"pending\",\"msg\":\"Hold BOOT for 5 seconds to confirm reset\"}");

  ledSolid(true);

  unsigned long btnDownTime = 0;
  bool btnWasDown = false;
  const unsigned long HOLD_REQUIRED = 5000;
  const unsigned long WAIT_TIMEOUT  = 60000;
  unsigned long waitStart = millis();

  while (true) {
    bool btnDown = (digitalRead(BOOT_BTN) == LOW);

    if (btnDown && !btnWasDown) {
      btnDownTime = millis();
    }

    if (btnDown) {
      unsigned long heldFor = millis() - btnDownTime;
      if (heldFor >= HOLD_REQUIRED) {
        break;
      }
    } else if (!btnDown && btnWasDown) {
      sendError("reset_cancelled");
      ledSolid(false);
      return;
    }

    if (!btnDown && (millis() - waitStart > WAIT_TIMEOUT)) {
      sendError("reset_cancelled");
      ledSolid(false);
      return;
    }

    btnWasDown = btnDown;

    // Very fast blink while awaiting reset confirmation
    static unsigned long lastBlink = 0;
    static bool blinkState = false;
    if (millis() - lastBlink > 30) {
      lastBlink = millis();
      blinkState = !blinkState;
      ledSolid(blinkState);
    }

    delay(5);
  }

  // Close any open Preferences handle before erasing
  prefs.end();

  // Erase the entire NVS partition — full partition-level wipe,
  // not a soft-delete. This is the correct factory reset approach.
  // (See RESEARCH.md Pitfall 5 for nvs_flash_erase() vs prefs.remove() distinction)
  nvs_flash_deinit();
  nvs_flash_erase();

  Serial.println("{\"status\":\"ok\",\"msg\":\"factory_reset_complete\"}");
  delay(100); // brief delay to flush serial before reboot

  esp_restart();
}

// handleEntropyCheck()
//   Runs the chi-squared entropy validation test and returns result.
void handleEntropyCheck() {
  if (validateEntropy()) {
    sendResponse("ok", "msg", "entropy_valid");
  } else {
    sendError("entropy_check_failed");
  }
}

// ---- Parse incoming serial command ----
void parseCommand(const char *line) {
  const char *cmdStart = strstr(line, "\"cmd\"");
  if (!cmdStart) { sendError("no_cmd"); return; }

  if (strstr(cmdStart, "\"ping\"")) {
    sendResponse("ok", "msg", "pong");
  }
  else if (strstr(cmdStart, "\"pubkey\"")) {
    handleGetPubkey();
  }
  else if (strstr(cmdStart, "\"generate\"")) {
    handleGenerateBip39();
  }
  else if (strstr(cmdStart, "\"sign\"")) {
    const char *payloadKey = strstr(line, "\"payload\"");
    if (!payloadKey) { sendError("no_payload"); return; }
    const char *valStart = strchr(payloadKey + 9, '"');
    if (!valStart) { sendError("bad_format"); return; }
    valStart++;
    const char *valEnd = strchr(valStart, '"');
    if (!valEnd) { sendError("bad_format"); return; }
    size_t hexLen = valEnd - valStart;
    handleSign(valStart, hexLen);
  }
  else if (strstr(cmdStart, "\"reset\"")) {
    handleFactoryReset();
  }
  else if (strstr(cmdStart, "\"entropy_check\"")) {
    handleEntropyCheck();
  }
  else {
    sendError("unknown_cmd");
  }
}

// ---- Perform signing (after button confirm) ----
void performSign() {
  uint8_t signature[64];
  Ed25519::sign(signature, privateKey, publicKey, pendingMessage, pendingMessageLen);

  char hexSig[129];
  hexEncode(signature, 64, hexSig);
  char hexPub[65];
  hexEncode(publicKey, 32, hexPub);

  Serial.print("{\"status\":\"signed\",\"signature\":\"");
  Serial.print(hexSig);
  Serial.print("\",\"pubkey\":\"");
  Serial.print(hexPub);
  Serial.println("\"}");

  state = IDLE;
  pendingMessageLen = 0;

  ledBlink(2, 150);
  ledSolid(true);
}

void rejectSign() {
  sendError("rejected");
  state = IDLE;
  pendingMessageLen = 0;
  ledBlink(5, 50);
  ledSolid(true);
}

// ---- Setup ----
void setup() {
  Serial.begin(115200);
  delay(2000);

  pinMode(LED_PIN, OUTPUT);
  pinMode(BOOT_BTN, INPUT_PULLUP);
  ledSolid(false);

  // Load keypair from encrypted NVS (with migration path for old plaintext keys).
  // Device starts without a key if NVS is empty — key generation is command-driven.
  if (!loadKeypair()) {
    hasKey = false;
  }

  // Boot banner (human-readable; host ignores lines not starting with '{')
  Serial.println("# UNRUGGABLE ESP32 v1.0 - BIP39 Hardware Signer");
  if (hasKey) {
    Serial.print("# Address: ");
    Serial.println(solanaAddress);
  } else {
    Serial.println("# No keypair loaded. Send generate command.");
  }
  Serial.println("# Ready for commands. Protocol: JSON lines.");
  Serial.println("# Commands: ping, pubkey, generate, sign, reset, entropy_check");

  ledSolid(hasKey);
}

// ---- Main loop ----
bool lastBtn = false;

void loop() {
  // ---- Read serial input (line-buffered) ----
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      if (serialBufIdx > 0) {
        serialBuf[serialBufIdx] = '\0';
        if (serialBuf[0] == '{') {
          parseCommand(serialBuf);
        }
        serialBufIdx = 0;
      }
    } else if (serialBufIdx < SERIAL_BUF_SIZE - 1) {
      serialBuf[serialBufIdx++] = c;
    }
  }

  // ---- Handle signing confirmation ----
  bool btnPressed = (digitalRead(BOOT_BTN) == LOW);

  if (state == AWAITING_CONFIRM) {
    // Button press = confirm
    if (btnPressed && !lastBtn) {
      performSign();
    }
    // Timeout = reject
    if (millis() - signRequestTime > SIGN_TIMEOUT_MS) {
      rejectSign();
    }
    // Slow pulse while waiting for confirmation
    static unsigned long lastPulse = 0;
    if (millis() - lastPulse > 300) {
      lastPulse = millis();
      static bool pulseState = false;
      pulseState = !pulseState;
      ledSolid(pulseState);
    }
  }

  lastBtn = btnPressed;
  delay(10);
}
