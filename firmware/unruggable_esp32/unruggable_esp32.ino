// Unruggable ESP32 - Phase 3: Hardware Transaction Signer
// Board: ESP32-C3 SuperMini
// Serial protocol for signing Solana transactions

#include <Preferences.h>
#include <Ed25519.h>

#define LED_PIN 8
#define BOOT_BTN 9
#define SIGN_TIMEOUT_MS 30000  // 30 seconds to confirm
#define SERIAL_BUF_SIZE 4096   // max incoming message size

Preferences prefs;

uint8_t privateKey[32];
uint8_t publicKey[32];
char solanaAddress[45];

bool hasKey = false;

// Serial protocol buffer
char serialBuf[SERIAL_BUF_SIZE];
int serialBufIdx = 0;

// Signing state
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

// ---- LED ----
void ledSolid(bool on) { digitalWrite(LED_PIN, on ? LOW : HIGH); }
void ledBlink(int times, int ms) {
  for (int i = 0; i < times; i++) {
    digitalWrite(LED_PIN, LOW); delay(ms);
    digitalWrite(LED_PIN, HIGH); delay(ms);
  }
}

// ---- Key management ----
void generateNewKeypair() {
  for (int i = 0; i < 32; i += 4) {
    uint32_t r = esp_random();
    privateKey[i] = (r >> 0) & 0xFF;
    privateKey[i + 1] = (r >> 8) & 0xFF;
    privateKey[i + 2] = (r >> 16) & 0xFF;
    privateKey[i + 3] = (r >> 24) & 0xFF;
  }
  Ed25519::derivePublicKey(publicKey, privateKey);
  size_t addrLen;
  base58Encode(publicKey, 32, solanaAddress, &addrLen);

  prefs.begin("unruggable", false);
  prefs.putBytes("privkey", privateKey, 32);
  prefs.putBytes("pubkey", publicKey, 32);
  prefs.end();
  hasKey = true;
}

bool loadKeypair() {
  prefs.begin("unruggable", true);
  size_t privLen = prefs.getBytes("privkey", privateKey, 32);
  size_t pubLen = prefs.getBytes("pubkey", publicKey, 32);
  prefs.end();
  if (privLen == 32 && pubLen == 32) {
    size_t addrLen;
    base58Encode(publicKey, 32, solanaAddress, &addrLen);
    hasKey = true;
    return true;
  }
  return false;
}

// ---- JSON response helpers (minimal, no library needed) ----
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

  // Notify host to wait
  Serial.print("{\"status\":\"pending\",\"msg\":\"Confirm on device\",\"bytes\":");
  Serial.print(pendingMessageLen);
  Serial.println("}");

  // Visual: fast blink to alert user
  ledBlink(5, 80);
  // LED stays on solid while waiting for button
  ledSolid(true);
}

void handleGenerate() {
  generateNewKeypair();
  char hexPub[65];
  hexEncode(publicKey, 32, hexPub);
  sendResponse("ok", "pubkey", hexPub, "address", solanaAddress);
}

// ---- Parse incoming serial command ----
// Protocol (JSON lines):
//   {"cmd":"pubkey"}
//   {"cmd":"sign","payload":"<hex-encoded message bytes>"}
//   {"cmd":"generate"}
//   {"cmd":"ping"}

void parseCommand(const char *line) {
  // Find cmd value
  const char *cmdStart = strstr(line, "\"cmd\"");
  if (!cmdStart) { sendError("no_cmd"); return; }

  if (strstr(cmdStart, "\"ping\"")) {
    sendResponse("ok", "msg", "pong");
  }
  else if (strstr(cmdStart, "\"pubkey\"")) {
    handleGetPubkey();
  }
  else if (strstr(cmdStart, "\"generate\"")) {
    handleGenerate();
  }
  else if (strstr(cmdStart, "\"sign\"")) {
    // Extract payload hex string
    const char *payloadKey = strstr(line, "\"payload\"");
    if (!payloadKey) { sendError("no_payload"); return; }
    const char *valStart = strchr(payloadKey + 9, '"');
    if (!valStart) { sendError("bad_format"); return; }
    valStart++; // skip opening quote
    const char *valEnd = strchr(valStart, '"');
    if (!valEnd) { sendError("bad_format"); return; }
    size_t hexLen = valEnd - valStart;
    handleSign(valStart, hexLen);
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

  // Confirm blink
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

  if (!loadKeypair()) {
    generateNewKeypair();
  }

  // Boot message (human-readable, not JSON — host ignores lines not starting with '{')
  Serial.println("# UNRUGGABLE ESP32 v0.3 - Hardware Signer");
  Serial.print("# Address: ");
  Serial.println(solanaAddress);
  Serial.println("# Ready for commands. Protocol: JSON lines.");

  ledSolid(true);
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
        // Only parse lines starting with '{'
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
    // Blink while waiting (slow pulse)
    static unsigned long lastPulse = 0;
    if (millis() - lastPulse > 300) {
      lastPulse = millis();
      static bool pulseState = false;
      pulseState = !pulseState;
      ledSolid(pulseState);
    }
  }

  // ---- Idle: hold boot 3s to regenerate key ----
  static unsigned long btnDownTime = 0;
  static bool btnHeld = false;
  if (state == IDLE) {
    if (btnPressed && !lastBtn) { btnDownTime = millis(); btnHeld = false; }
    if (btnPressed && !btnHeld && (millis() - btnDownTime > 3000)) {
      btnHeld = true;
      handleGenerate();
    }
  }

  lastBtn = btnPressed;
  delay(10);
}
