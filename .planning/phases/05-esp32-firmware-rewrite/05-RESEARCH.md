# Phase 5: ESP32 Firmware Rewrite - Research

**Researched:** 2026-03-20
**Domain:** ESP32-C3 Arduino firmware (BIP39/SLIP-0010 crypto), Rust hardware bridge extensions, Flutter UI (mnemonic backup, device dashboard, auto-connect, screenshot prevention)
**Confidence:** HIGH (firmware crypto patterns), MEDIUM (screenshot prevention on macOS desktop)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Mnemonic backup flow**
- 12-word mnemonic (not 24)
- All 12 words displayed on a single screen, numbered
- Verification quiz after display: user selects correct word for 3-4 random positions before proceeding
- Screenshots blocked on the mnemonic screen (FLAG_SECURE / platform screenshot prevention)
- Mnemonic shown exactly once during setup — after quiz, it's never retrievable from the app

**Firmware architecture**
- All crypto runs on ESP32 — BIP39 generation, SLIP-0010 derivation, seed storage. Private key never leaves the device.
- ESP32 generates mnemonic from its own hardware entropy, sends words to host for display only
- Entropy: `esp_fill_random()` (true hardware RNG on ESP32-C3) with runtime randomness test at boot; firmware refuses to generate if test fails (LED error pattern)
- Seed encrypted with AES-256 using a key derived from ESP32-C3's unique eFuse ID (hardware AES acceleration available)
- Factory reset: `nvs_flash_erase_partition()` erases entire NVS partition (not soft-delete)
- Factory reset trigger: app sends reset command + user must hold BOOT button for 5 seconds to confirm (two-factor: software + physical)
- Derivation path: `m/44'/501'/0'/0'` (Solana standard, single key for v1)
- Firmware stays on Arduino framework (no migration to ESP-IDF)

**Device lifecycle**
- Auto-connect: background USB port scan on app launch, silent connect if registered device found (no user prompt)
- Pubkey mismatch on reconnect: persistent warning banner + block all signing until resolved; offer re-register or disconnect
- Unexpected disconnect: toast notification "Hardware wallet disconnected", pending signing fails with clear error, sidebar updates
- Poll rate: every 5 seconds for connection status

**Hardware Wallet sidebar**
- Always visible in sidebar, even when no device is paired (HWLT-06)
- 3 states: not paired (setup CTA badge), paired+disconnected (grayed USB icon, device name), connected (primary-color USB icon, device name)
- Tapping opens a device dashboard: device info (name, pubkey, connection status), actions (generate new key, factory reset, disconnect)
- When unpaired, dashboard shows setup guide flow

### Claude's Discretion
- Exact LED feedback patterns for entropy failure, signing, generation
- Randomness test algorithm (chi-squared or similar)
- eFuse key derivation specifics (HKDF or similar)
- Device dashboard layout and component structure
- Toast vs snackbar implementation for disconnect notification

### Deferred Ideas (OUT OF SCOPE)
- Multiple pubkeys per seed (HWLT-V2-01) — SLIP-0010 derivation path indices
- Multi-device support
- Firmware flashing through the app
- HD wallet derivation from mnemonic
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| HWLT-01 | Previously paired ESP32 silently auto-connects on app launch | Riverpod StreamNotifier with Timer.periodic inside build(); scan → connect → compare stored pubkey |
| HWLT-02 | UI updates connection status when ESP32 connects/disconnects | hwConnectionProvider drives sidebar state; `ref.invalidateSelf()` on each poll tick |
| HWLT-03 | App verifies device pubkey matches registered wallet address on reconnect | After auto-connect, compare `esp32_bridge.address()` vs `WalletInfo.address`; surface mismatch banner |
| HWLT-04 | User can generate new keypair on ESP32 with BIP39 mnemonic backup | New `generate` firmware command returns 12 words; Flutter mnemonic display + quiz screen |
| HWLT-05 | Mnemonic displayed once during setup for user to write down | One-shot flow: words displayed, quiz passed, words cleared from Dart state |
| HWLT-06 | Hardware Wallet has its own sidebar entry (always visible, guides setup if not connected) | New permanent drawer entry; 3-state widget driven by hwConnectionProvider |
| INFR-01 | ESP32 firmware supports BIP39 mnemonic generation and SLIP-0010 key derivation | BIP39 in C (wordlist + checksum), HMAC-SHA512 SLIP-0010 chain — all verified from mnemonic.rs reference |
| INFR-02 | ESP32 firmware uses verified entropy source (not silently weak esp_random) | `bootloader_random_enable()` at boot + chi-squared statistical test on 256 bytes of output |
| INFR-03 | ESP32 seed stored encrypted in NVS (not plaintext) | AES-256-CBC via mbedtls; key derived from MAC+salt via HMAC-SHA256; NVS stores ciphertext + IV |
</phase_requirements>

---

## Summary

Phase 5 rewrites the ESP32 firmware from a simple key generator into a proper BIP39 hardware wallet and wires a complete Flutter UI around it. The work spans three distinct domains: (1) Arduino C firmware rewrite implementing BIP39 generation, SLIP-0010 derivation, AES-256 NVS encryption, and entropy validation; (2) Rust bridge extensions adding `generateHardwareKeypair`, `getHardwareMnemonic`, `factoryResetHardware`, and a connection-state polling mechanism; and (3) three new Flutter screens — mnemonic display, verification quiz, and device dashboard — plus a permanent Hardware Wallet sidebar entry.

The existing firmware (`unruggable_esp32.ino`) already has the scaffolding: JSON line protocol, LED helpers, button handling, NVS via `Preferences`, and Ed25519 signing. The rewrite extends this scaffold rather than replacing it wholesale. The Rust `mnemonic.rs` is the definitive reference for all crypto logic — the C port follows it algorithm-for-algorithm.

The most technically subtle area is entropy quality. The ESP32-C3's `esp_fill_random()` requires an active entropy source (RF subsystem, SAR ADC via `bootloader_random_enable()`, or bootloader-phase timing). Without one, output is pseudo-random only. The firmware must call `bootloader_random_enable()` at init, sample 256 bytes, run a statistical test, then call `bootloader_random_disable()` before enabling any other peripheral. Failure must halt generation with a loud LED error. The AES-256 seed encryption approach (mbedtls via Arduino) is well-established and available without ESP-IDF migration.

**Primary recommendation:** Implement BIP39/SLIP-0010 directly in C (port mnemonic.rs algorithms), use mbedtls AES-256-CBC for seed encryption keyed from MAC+HMAC-SHA256, validate entropy via chi-squared test at boot, and expose everything through the existing JSON line protocol with three new commands.

---

## Standard Stack

### Core (Firmware — Arduino C)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Arduino-ESP32 core | 2.x / 3.x | ESP32-C3 HAL, `Preferences`, `esp_fill_random`, `esp_efuse_mac_get_default` | Already in use; the locked decision is to stay on Arduino |
| mbedtls (bundled) | 2.x (bundled with ESP-IDF/Arduino) | AES-256-CBC + HMAC-SHA256 for seed encryption | Bundled with every arduino-esp32 install; hardware-accelerated on C3; no extra dependency |
| Ed25519 (existing) | already in firmware | Ed25519 signing | Already present; no change needed |
| BIP39 wordlist (hand-ported) | N/A | 2048-word BIP39 English wordlist in C array | No Arduino BIP39 library is well-maintained; hand-port is ~60KB PROGMEM; mnemonic.rs is the reference |

### Core (Rust Bridge extensions)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| serialport | 4.x (already in Cargo.toml) | Serial comms with ESP32 | Already in use |
| serde / serde_json | 1.x (already in Cargo.toml) | JSON command/response encoding | Already in use |
| deadbolt_core hardware module | existing | Esp32Bridge, Esp32Detector, Esp32Signer | The bridge pattern is established; just add new commands |

### Core (Flutter)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter_riverpod | 2.5.1 (existing) | State management, periodic polling provider | Already in use; StreamNotifier pattern for auto-connect |
| go_router | 14.2.0 (existing) | Routing for new screens | Already in use |
| no_screenshot | ^1.0.0 | Screenshot prevention on mnemonic screen; supports macOS desktop | Only actively maintained Flutter package with confirmed macOS desktop support |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `bootloader_random.h` (ESP-IDF component) | bundled | `bootloader_random_enable/disable()` for entropy sourcing | Only needed at key generation time; disable after sampling |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| mbedtls AES-256-CBC | Hardware-only flash encryption (XTS-AES) | Flash encryption is device-global, affects whole partition, not application-accessible for per-key ops; mbedtls is correct choice |
| `no_screenshot` | Custom platform channel to NSWindow | Platform channel gives more control but requires writing Swift/ObjC; no_screenshot is maintained and works on macOS |
| Hand-ported BIP39 wordlist | howech/bip39 Arduino library | Arduino library is 2018, 2 commits, unmaintained; hand-port from the BIP39 spec is ~150 lines + wordlist array |

**Installation (Flutter only — firmware and Rust have no new installs):**
```bash
flutter pub add no_screenshot
```

---

## Architecture Patterns

### Recommended Project Structure

**New firmware additions (in `unruggable_esp32.ino`):**
```
firmware/unruggable_esp32/
├── unruggable_esp32.ino    # Main file — add generate/mnemonic/reset/entropy_check handlers
├── bip39_wordlist.h        # 2048-word C array (PROGMEM)
├── bip39.h / bip39.cpp     # BIP39 generation + SLIP-0010 derivation
└── nvs_crypto.h / .cpp     # AES-256-CBC encrypt/decrypt for NVS seed storage
```

**New Rust bridge functions (in `rust/deadbolt_bridge/src/api/hardware.rs`):**
```
hardware.rs                 # Add: generate_hardware_keypair(), get_hardware_mnemonic(),
                            #      factory_reset_hardware(), get_connection_state()
```

**New Flutter screens:**
```
lib/features/hardware/
├── hardware_wallet_screen.dart     # Device dashboard (3-state entry point)
├── mnemonic_display_screen.dart    # Show 12 words once, screenshot blocked
└── mnemonic_quiz_screen.dart       # 3-4 word verification quiz
lib/providers/
└── hardware_connection_provider.dart  # StreamNotifier polling connection state
```

### Pattern 1: Entropy Validation at Boot (Firmware)

**What:** Call `bootloader_random_enable()`, sample 256 bytes, run chi-squared test, call `bootloader_random_disable()`. Refuse generation if test fails.

**When to use:** Once at `setup()` before any key generation, and again inside `handleGenerate()`.

**Example (chi-squared approach):**
```c
// Source: Espressif ESP-IDF RNG docs + standard statistical testing
bool validateEntropy() {
  bootloader_random_enable();
  uint8_t samples[256];
  esp_fill_random(samples, 256);
  bootloader_random_disable();

  // Chi-squared test: count byte frequency, expect ~1.0 per value
  uint16_t freq[256] = {0};
  for (int i = 0; i < 256; i++) freq[samples[i]]++;

  float chi2 = 0.0f;
  float expected = 1.0f; // 256 samples / 256 possible values
  for (int i = 0; i < 256; i++) {
    float diff = freq[i] - expected;
    chi2 += (diff * diff) / expected;
  }
  // chi2 for 255 DOF: p=0.001 threshold ~350; reject if > 350
  return chi2 < 350.0f;
}
```

### Pattern 2: BIP39 Generation in C (Firmware)

**What:** Port `mnemonic.rs` generate(12) algorithm directly to C. Entropy → checksum → 12 indices → word lookup.

**Algorithm (verified against mnemonic.rs reference):**
```c
// Source: BIP-0039 spec + mnemonic.rs reference implementation
// 128 bits entropy → 4-bit checksum (SHA256[0] >> 4) → 132 bits → 12 × 11-bit indices
void generateMnemonic(uint8_t* entropy16, char words[12][10]) {
  uint8_t hash[32];
  // SHA256 of entropy for checksum
  mbedtls_sha256(entropy16, 16, hash, 0);

  // Pack entropy + checksum into bit stream (132 bits = 16.5 bytes)
  uint8_t bits[17] = {0};
  memcpy(bits, entropy16, 16);
  bits[16] = hash[0] & 0xF0; // top 4 bits of hash

  // Extract 12 × 11-bit word indices
  for (int i = 0; i < 12; i++) {
    int bitOffset = i * 11;
    int byteIdx = bitOffset / 8;
    int bitShift = bitOffset % 8;
    uint16_t idx = ((bits[byteIdx] << 8) | bits[byteIdx+1]) >> (5 - bitShift);
    idx &= 0x7FF; // mask to 11 bits
    strncpy(words[i], BIP39_WORDLIST[idx], 9);
  }
}
```

### Pattern 3: SLIP-0010 Derivation in C (Firmware)

**What:** Port `derive_keypair()` from mnemonic.rs to C. BIP39 seed → HMAC-SHA512 master → 4 hardened derivation steps.

**Key insight (from mnemonic.rs):** The SLIP-0010 curve domain separator for Ed25519 is the string literal `"ed25519 seed"` (12 bytes). Hardened child derivation: `data = 0x00 || parent_key || (index + 0x80000000)` in big-endian.

```c
// Source: mnemonic.rs derive_keypair() — algorithmic port
// Path: m/44'/501'/0'/0'
static const uint32_t DERIV_PATH[4] = {44, 501, 0, 0};

void slip10Derive(uint8_t* bip39seed64, uint8_t* privkeyOut32) {
  uint8_t I[64];
  // Master key
  mbedtls_md_hmac(mbedtls_md_info_from_type(MBEDTLS_MD_SHA512),
    (uint8_t*)"ed25519 seed", 12, bip39seed64, 64, I);

  uint8_t key[32], chain[32];
  memcpy(key, I, 32);
  memcpy(chain, I + 32, 32);

  for (int d = 0; d < 4; d++) {
    uint32_t hIndex = DERIV_PATH[d] + 0x80000000UL;
    uint8_t data[37];
    data[0] = 0x00;
    memcpy(data + 1, key, 32);
    data[33] = (hIndex >> 24) & 0xFF;
    data[34] = (hIndex >> 16) & 0xFF;
    data[35] = (hIndex >>  8) & 0xFF;
    data[36] = (hIndex      ) & 0xFF;
    mbedtls_md_hmac(mbedtls_md_info_from_type(MBEDTLS_MD_SHA512),
      chain, 32, data, 37, I);
    memcpy(key, I, 32);
    memcpy(chain, I + 32, 32);
  }
  memcpy(privkeyOut32, key, 32);
  // Zeroize key/chain after use
  memset(key, 0, 32); memset(chain, 0, 32);
}
```

### Pattern 4: AES-256-CBC Seed Encryption (Firmware)

**What:** Derive 32-byte AES key from device MAC using HMAC-SHA256 with a fixed salt. Encrypt the 64-byte BIP39 seed with AES-256-CBC. Store ciphertext + IV in NVS.

**Why not flash encryption:** Flash encryption (XTS-AES) is device-global and not accessible for application-level per-key encryption. mbedtls AES-256-CBC is the correct approach for Arduino-level NVS encryption.

```c
// Source: mbedtls docs + ESP32 forum established patterns
// Key derivation: HMAC-SHA256(key=MAC[6], msg="deadbolt-nvs-v1")
void deriveEncKey(uint8_t keyOut32[32]) {
  uint8_t mac[6];
  esp_efuse_mac_get_default(mac);
  const char* SALT = "deadbolt-nvs-v1";
  mbedtls_md_hmac(mbedtls_md_info_from_type(MBEDTLS_MD_SHA256),
    mac, 6, (uint8_t*)SALT, strlen(SALT), keyOut32);
}

// Encrypt seed (64 bytes) → 80 bytes ciphertext (AES-256-CBC, PKCS7 pad)
// Store: 16-byte IV + 80-byte ciphertext in NVS
```

**Security note (LOW confidence):** Keying from the MAC address means the key is device-specific but not secret from someone with physical access. This is consistent with the CONTEXT.md decision (eFuse ID-based). The encryption deters casual NVS readout; it does not protect against a determined adversary with flash dump capability. This tradeoff is acceptable for v1 given the single-device use case.

### Pattern 5: Rust Bridge — New Commands

**What:** Extend `hardware.rs` in `deadbolt_bridge` with three new pub async functions following the established FRB pattern.

```rust
// Source: existing hardware.rs pattern + esp32_bridge.rs
pub async fn generate_hardware_keypair(port_path: String) -> Result<Vec<String>, String> {
    // Send {"cmd":"generate"} — firmware returns mnemonic words
    // Returns 12 words for Flutter display
}

pub async fn factory_reset_hardware(port_path: String) -> Result<(), String> {
    // Send {"cmd":"reset"} — firmware awaits 5s BOOT hold, then erases NVS
}
```

**Important:** Add new commands to `esp32_bridge.rs` `Response` struct: `words: Option<Vec<String>>` field for mnemonic response.

### Pattern 6: Flutter Hardware Connection Provider

**What:** A `StreamNotifierProvider` that polls for the registered hardware wallet every 5 seconds and emits `HardwareConnectionState`.

```dart
// Source: Riverpod StreamNotifier docs + existing hwDetectedProvider pattern
enum HwConnState { notPaired, disconnected, connected, pubkeyMismatch }

@riverpod
class HardwareConnectionNotifier extends _$HardwareConnectionNotifier {
  @override
  Stream<HwConnState> build() async* {
    yield await _checkConnection();
    await for (final _ in Stream.periodic(const Duration(seconds: 5))) {
      yield await _checkConnection();
    }
  }
  // ...
}
```

**Note:** `ref.onDispose` is not needed for `Stream.periodic` inside `build()` — Riverpod automatically cancels the stream when the provider is disposed.

### Pattern 7: Flutter Mnemonic Display with Screenshot Prevention

**What:** Use `no_screenshot` package to block screenshots on the mnemonic display screen only (not globally). Enable on screen enter, disable on screen exit.

```dart
// Source: no_screenshot package docs (v1.0.0, confirmed macOS support)
import 'package:no_screenshot/no_screenshot.dart';

class MnemonicDisplayScreen extends ConsumerStatefulWidget { ... }
class _MnemonicDisplayScreenState extends ConsumerState<MnemonicDisplayScreen> {
  final _noScreenshot = NoScreenshot.instance;

  @override
  void initState() {
    super.initState();
    _noScreenshot.screenshotOff();
  }

  @override
  void dispose() {
    _noScreenshot.screenshotOn();
    super.dispose();
  }
  // ...
}
```

**Confidence note:** `no_screenshot` v1.0.0 claims macOS desktop support. However, macOS does not have an OS-level API equivalent to Android's `FLAG_SECURE`. On macOS, the package likely uses `NSWindow.sharingType = .none` (window content protection). This prevents system screenshot tools and screen sharing but may not prevent third-party capture tools. This is acceptable for v1 — the primary goal is preventing accidental screenshots.

### Anti-Patterns to Avoid

- **Storing mnemonic words in Dart state after quiz completion:** Words must be explicitly zeroed/nulled from the provider state once the quiz is passed. Use `ref.invalidate()` or clear the state immediately.
- **Storing the private key in NVS in plaintext:** The current firmware does this. The rewrite must always encrypt before `putBytes`.
- **Using `esp_random()` without verifying entropy source:** Current firmware generates keys this way. The rewrite must call `bootloader_random_enable()` before sampling for key generation.
- **Using `prefs.remove("privkey")` for factory reset:** This is a soft-delete — flash retains the data until sector rewrite. Use `nvs_flash_erase_partition()` for a true wipe.
- **Re-reading mnemonic from firmware after setup:** The architecture decision is that the mnemonic is shown once from the generate response. The firmware should NOT store words in NVS or return them on subsequent `pubkey` requests.
- **Assuming NVS partition name:** The default Arduino `Preferences` namespace uses the NVS partition labeled "nvs". `nvs_flash_erase_partition()` needs the partition label — use `nvs_flash_erase_partition_ptr()` with `esp_partition_find_first()` for the "nvs" label.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| AES-256 encryption on ESP32 | Custom AES implementation | mbedtls bundled with arduino-esp32 | mbedtls is constant-time, hardware-accelerated, already present |
| SHA-256 / HMAC-SHA256 on ESP32 | Custom hash | mbedtls `mbedtls_sha256` / `mbedtls_md_hmac` | Same as above |
| PBKDF2 for BIP39 seed from mnemonic | Custom PBKDF2 | mbedtls `mbedtls_pkcs5_pbkdf2_hmac` | BIP39 seed derivation is PBKDF2-HMAC-SHA512, 2048 iterations — mbedtls provides this |
| Screenshot prevention on macOS Flutter | Platform channel to NSWindow | `no_screenshot` package | Package handles platform differences; saves writing Swift glue code |
| Timer-based polling Riverpod provider | Manage timers manually in widgets | `StreamNotifier` with `Stream.periodic` | Riverpod owns the lifecycle, auto-cancels on dispose; no timer leaks |

**Key insight:** The entire crypto stack (BIP39, PBKDF2, HMAC-SHA512, SLIP-0010, AES-256-CBC, SHA-256) is available through mbedtls, which ships with arduino-esp32. No new libraries need to be added to the firmware project.

---

## Common Pitfalls

### Pitfall 1: Entropy Source Not Active During Key Generation

**What goes wrong:** `esp_fill_random()` called when neither Wi-Fi/BT is enabled nor `bootloader_random_enable()` has been called — output is pseudo-random only.

**Why it happens:** The current firmware calls `esp_random()` directly in `generateNewKeypair()` with no entropy checks. Arduino setup() runs after the bootloader has finished, so the bootloader entropy source is already disabled.

**How to avoid:** Call `bootloader_random_enable()` at the start of `handleGenerate()`, sample entropy for the chi-squared test, then call `bootloader_random_disable()` before proceeding. Fail loudly if the test rejects.

**Warning signs:** Chi-squared score consistently high (> 350 for 256 samples); byte frequency distribution visibly non-uniform in testing.

### Pitfall 2: BIP39 Seed Is 64 Bytes, Private Key Is 32 Bytes

**What goes wrong:** Confusing the BIP39 seed (PBKDF2 output = 64 bytes) with the SLIP-0010 derived private key (HMAC output left half = 32 bytes). Storing the wrong value.

**Why it happens:** Two different "seeds" in the pipeline. mnemonic.rs `to_seed()` returns 64 bytes; `derive_keypair()` reduces to 32 bytes via HMAC chain.

**How to avoid:** In the C port, always label buffers clearly: `bip39_seed[64]` vs `ed25519_key[32]`. Only store `ed25519_key[32]` in NVS (encrypted). Zeroize `bip39_seed` immediately after SLIP-0010 derivation.

### Pitfall 3: PBKDF2 Stack Overflow on ESP32

**What goes wrong:** PBKDF2-HMAC-SHA512 with 2048 iterations is computationally intensive. Running it on a small stack frame causes silent stack overflow.

**Why it happens:** ESP32-C3 has limited stack depth. mbedtls PBKDF2 requires ~2KB of stack internally.

**How to avoid:** Either increase the Arduino task stack size (xTaskCreatePinnedToCore with larger stack) or call mbedtls PBKDF2 from the main loop where the stack is large. Do not call it from an interrupt or a sub-task with default stack.

### Pitfall 4: JSON Response Size for Mnemonic Words

**What goes wrong:** 12 words as a JSON array exceeds the 4096-byte `SERIAL_BUF_SIZE` on the Rust host side if each word is ~8 chars.

**Why it happens:** Current `SERIAL_BUF_SIZE = 4096` bytes in the firmware. A 12-word mnemonic response like `{"status":"ok","words":["abandon","abandon",...]}` is ~160 bytes — fine. But the host-side read buffer and chunked read logic need to handle multi-line words gracefully.

**How to avoid:** Return words as a JSON array in a single line. `{"status":"ok","words":["word1",...,"word12"]}` is well within limits. The Rust bridge's `read_response()` reads one line at a time — this works cleanly.

### Pitfall 5: NVS Partition Label vs Namespace

**What goes wrong:** `nvs_flash_erase_partition("nvs")` vs `nvs_flash_erase_partition_ptr()` confusion. Arduino's `Preferences` uses a namespace within the NVS partition, not the partition label.

**Why it happens:** NVS has two levels: the flash partition (label "nvs") and namespaces within it (like "unruggable"). `nvs_flash_erase_partition()` operates at the partition level — it erases everything.

**How to avoid:** For factory reset, use the correct call sequence:
```c
// Close any open Preferences first
prefs.end();
// Erase entire NVS partition by label
const esp_partition_t* nvs_part = esp_partition_find_first(
  ESP_PARTITION_TYPE_DATA, ESP_PARTITION_SUBTYPE_DATA_NVS, "nvs");
if (nvs_part) esp_partition_erase_range(nvs_part, 0, nvs_part->size);
```
Then restart the device.

### Pitfall 6: Mnemonic Words Lingering in Dart/Rust State

**What goes wrong:** Mnemonic words returned from `generateHardwareKeypair()` get cached in Rust bridge state or Riverpod provider cache. A second call to `walletListProvider` might re-expose them.

**Why it happens:** FRB bridge functions return `Vec<String>` to Dart. If a provider holds a reference, words stay in memory.

**How to avoid:** Mnemonic words are returned in a one-shot response. The Flutter screen must `ref.invalidate(hardwareConnectionProvider)` after quiz completion and must NOT store words in any persisted provider. Clear local Dart state after the quiz.

### Pitfall 7: Auto-Connect Blocking the UI Thread

**What goes wrong:** The `Esp32Bridge::connect()` call (serial port open + ping + pubkey fetch) takes 500ms–2s. If called synchronously on app launch, it blocks the UI.

**Why it happens:** The existing `connectHardwareWallet()` function is synchronous. Making it part of an auto-connect flow without `async` wrapping freezes the Flutter UI.

**How to avoid:** All new bridge functions for connection must be `pub async fn`. The Flutter provider uses `await` via FRB's async bridge. The existing `sign_serialized_transaction_hardware` is already blocking — auto-connect must not use it directly.

---

## Code Examples

Verified patterns from official sources or existing codebase:

### BIP39 → Seed via PBKDF2 (mbedtls)
```c
// Source: mnemonic.rs to_seed() + mbedtls PKCS5 PBKDF2
// mbedtls_pkcs5_pbkdf2_hmac is available in arduino-esp32 bundled mbedtls
void mnemonicToSeed(const char* mnemonic, uint8_t seed[64]) {
  const char* passphrase = "mnemonic"; // BIP39 standard prefix
  mbedtls_md_context_t ctx;
  mbedtls_md_init(&ctx);
  mbedtls_md_setup(&ctx, mbedtls_md_info_from_type(MBEDTLS_MD_SHA512), 1);
  mbedtls_pkcs5_pbkdf2_hmac(&ctx,
    (uint8_t*)mnemonic, strlen(mnemonic),
    (uint8_t*)passphrase, strlen(passphrase),
    2048, 64, seed);
  mbedtls_md_free(&ctx);
}
```

### Rust Bridge — New Response Fields
```rust
// Source: esp32_bridge.rs existing Response struct — extend for new commands
#[derive(Deserialize, Debug)]
struct Response {
    status: String,
    #[serde(default)]
    msg: Option<String>,
    #[serde(default)]
    pubkey: Option<String>,
    #[serde(default)]
    address: Option<String>,
    #[serde(default)]
    signature: Option<String>,
    // NEW:
    #[serde(default)]
    words: Option<Vec<String>>,
}
```

### Flutter Mnemonic Quiz Pattern
```dart
// Source: mnemonic.rs random_words() concept ported to Dart
// The Rust bridge exposes random_words() — use it for distractors
// Quiz: 3-4 positions chosen at random; each presents 4 options (1 correct + 3 random)
List<int> quizPositions = List.generate(12, (i) => i)..shuffle();
quizPositions = quizPositions.take(3).toList()..sort();
```

### Flutter Snackbar for Disconnect Notification
```dart
// Source: existing brand_theme.dart + Flutter ScaffoldMessenger pattern
// The decision allows "toast vs snackbar" as Claude's discretion — use ScaffoldMessenger
ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(
    content: Text('Hardware wallet disconnected'),
    duration: Duration(seconds: 3),
    backgroundColor: BrandColors.error,
  ),
);
```

### NVS Factory Reset — Correct Sequence
```c
// Source: ESP-IDF NVS flash docs
// Must: 1) close Preferences, 2) erase partition, 3) restart
prefs.end();
nvs_flash_deinit();
nvs_flash_erase(); // erases default "nvs" partition
// Then: esp_restart()
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Direct `esp_random()` for key gen (current firmware) | `bootloader_random_enable()` + statistical test + `esp_fill_random()` | INFR-02 decision | Keys generated from verified entropy |
| Raw private key stored in NVS plaintext (current firmware) | AES-256-CBC encrypted, key from MAC+HMAC | INFR-03 decision | Deters casual NVS readout |
| NVS soft-delete via `prefs.remove()` | Full partition erase via `nvs_flash_erase()` | INFR-03 / factory reset decision | True key destruction |
| Arbitrary Ed25519 key via `Ed25519::derivePublicKey()` (current) | BIP39 mnemonic → PBKDF2 seed → SLIP-0010 Ed25519 derivation | INFR-01 decision | User can recover wallet from 12 words |
| `hwDetectedProvider` — any ESP32 VID/PID (current) | `hardwareConnectionProvider` — compares pubkey to registered wallet | HWLT-03 decision | Detects replaced/swapped devices |

**Deprecated/outdated in this phase:**
- Current `generateNewKeypair()` in firmware: replaces with BIP39-based generation
- Current `loadKeypair()` / plaintext NVS read: replaces with encrypted NVS read
- Current `handleGenerate()` — key-on-button-hold: replaces with command-driven + physical 5s confirm

---

## Open Questions

1. **PBKDF2 timing on ESP32-C3**
   - What we know: PBKDF2-HMAC-SHA512 with 2048 iterations takes ~1-3 seconds on ESP32 at 160MHz; mbedtls hardware acceleration helps SHA but not the full PBKDF2 loop
   - What's unclear: Exact timing on ESP32-C3 SuperMini; whether the serial timeout needs extending during keypair generation
   - Recommendation: During `handleGenerate()`, send an immediate `{"status":"generating"}` response so the Rust bridge knows to extend its read timeout. Set a 30-second timeout for the final response.

2. **`bootloader_random_enable()` availability in Arduino framework**
   - What we know: The function is defined in `bootloader_random.h` which is an ESP-IDF component bundled with arduino-esp32
   - What's unclear: Whether it's exposed in the Arduino includes without explicit `extern "C"` linkage; STATE.md blocker note: "Verify esp-hal 1.0.0 USB Serial/JTAG under `unstable` feature gate" — this was for a different approach; Arduino stays on `esp_fill_random` path
   - Recommendation: Test `#include "bootloader_random.h"` in a minimal sketch at the start of the firmware wave. If not directly includable, use the alternative: enable Wi-Fi briefly with `WiFi.mode(WIFI_STA)` as entropy source, then `WiFi.mode(WIFI_OFF)` after sampling. This is a known Arduino ESP32 pattern.

3. **macOS screenshot prevention effectiveness**
   - What we know: `no_screenshot` v1.0.0 claims macOS support; likely uses `NSWindow.sharingType = .none`
   - What's unclear: Whether this prevents all capture methods on macOS (e.g., QuickTime screen recording, third-party tools)
   - Recommendation: Accept the limitation for v1. Add a visible disclaimer: "Screenshot blocked — write down your words." The primary risk is accidental screenshot to iCloud Photos, which this prevents.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Rust: `cargo test` (built-in); Flutter: `flutter test` (flutter_test) |
| Config file | No additional config — existing test infrastructure |
| Quick run command | `cd /Users/jo/Projects/deadbolt/rust && cargo test -p deadbolt_core -- hardware` |
| Full suite command | `cd /Users/jo/Projects/deadbolt/rust && cargo test && cd .. && flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HWLT-01 | Auto-connect: scan → match registered pubkey → silent connect | unit (Rust) | `cargo test -p deadbolt_core -- hardware::esp32_detector` | ✅ esp32_detector.rs has scan test |
| HWLT-02 | Sidebar state reflects connection status | smoke (Flutter) | `flutter test test/hardware_connection_provider_test.dart` | ❌ Wave 0 |
| HWLT-03 | Pubkey mismatch detected on reconnect | unit (Rust) | `cargo test -p deadbolt_bridge -- hardware::pubkey_mismatch` | ❌ Wave 0 |
| HWLT-04 | Generate command returns 12 BIP39 words | manual (requires device) | Manual — firmware test only | N/A |
| HWLT-05 | Mnemonic display: words cleared after quiz | smoke (Flutter) | `flutter test test/mnemonic_quiz_test.dart` | ❌ Wave 0 |
| HWLT-06 | Hardware Wallet sidebar entry always visible | smoke (Flutter) | `flutter test test/wallet_drawer_test.dart` | ❌ Wave 0 |
| INFR-01 | BIP39 + SLIP-0010 correct derivation (C port) | manual firmware + Rust cross-check | Compare `derive_keypair` output for test vector `abandon×11 about` | Manual |
| INFR-02 | Entropy test rejects bad RNG | unit (firmware) | Firmware serial test (manual with forced bad entropy mock) | Manual |
| INFR-03 | Encrypted NVS round-trip | unit (Rust) | `cargo test -p deadbolt_core -- hardware::nvs_crypto` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `cd /Users/jo/Projects/deadbolt/rust && cargo test -p deadbolt_core`
- **Per wave merge:** `cd /Users/jo/Projects/deadbolt/rust && cargo test && cd .. && flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/hardware_connection_provider_test.dart` — covers HWLT-02: provider emits correct state sequence
- [ ] `test/mnemonic_quiz_test.dart` — covers HWLT-05: words cleared after quiz pass; quiz requires correct selection
- [ ] `test/wallet_drawer_test.dart` — covers HWLT-06: Hardware Wallet entry visible when no device paired; 3 state variations
- [ ] `rust/deadbolt_core/src/hardware/` — add unit tests for pubkey mismatch logic (HWLT-03) and NVS crypto round-trip (INFR-03)

*(Note: HWLT-04 / INFR-01 / INFR-02 require physical ESP32 hardware — these are manual-only tests. The critical algorithmic correctness check for INFR-01 is: run the Rust `derive_keypair` test vector against the known Solana standard vector for `abandon×11 about` at path `m/44'/501'/0'/0'` — the C port must produce identical output.)*

---

## Sources

### Primary (HIGH confidence)
- [Espressif ESP-IDF RNG docs (ESP32-C3 stable)](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c3/api-reference/system/random.html) — entropy conditions, `esp_fill_random`, bootloader_random_enable
- [Espressif HMAC peripheral docs (ESP32-C3)](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c3/api-reference/peripherals/hmac.html) — eFuse key access patterns
- `rust/deadbolt_core/src/crypto/mnemonic.rs` — definitive reference for BIP39 + SLIP-0010 algorithm in this project
- `firmware/unruggable_esp32/unruggable_esp32.ino` — existing firmware scaffold, protocol, and patterns
- `rust/deadbolt_bridge/src/api/hardware.rs` — FRB bridge pattern to follow for new functions
- `lib/providers/wallet_provider.dart` — Riverpod provider patterns to follow

### Secondary (MEDIUM confidence)
- [no_screenshot pub.dev page](https://pub.dev/packages/no_screenshot) — macOS desktop support confirmed, v1.0.0
- [Riverpod StreamNotifier docs](https://riverpod.dev/docs/concepts2/providers) — Stream.periodic polling pattern
- [Espressif NVS flash docs (stable)](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/storage/nvs_flash.html) — `nvs_flash_erase_partition()` semantics
- [Espressif Flash Encryption docs (ESP32-C3)](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c3/security/flash-encryption.html) — why application-level AES (not flash encryption) is the right approach for NVS

### Tertiary (LOW confidence — verify before use)
- PBKDF2 timing estimate on ESP32-C3: 1-3 seconds derived from general ESP32 benchmarks; measure at implementation time
- `bootloader_random.h` direct include availability in arduino-esp32: needs a quick compile test to confirm include path

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — firmware uses bundled mbedtls (verified); Flutter `no_screenshot` v1.0.0 confirmed macOS support; Rust bridge follows existing patterns
- Architecture: HIGH — all patterns derived from existing codebase (mnemonic.rs, esp32_bridge.rs) or official Espressif docs
- Pitfalls: HIGH — entropy source requirement is official Espressif docs; NVS erase semantics from official docs; remaining pitfalls from direct codebase inspection
- Screenshot prevention (macOS): MEDIUM — macOS limitation is real; `no_screenshot` package claim unverified at code level

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (stable domain — mbedtls, BIP39 spec, SLIP-0010 spec are all stable; Riverpod API is stable)
