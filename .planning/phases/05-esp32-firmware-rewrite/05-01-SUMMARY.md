---
phase: 05-esp32-firmware-rewrite
plan: 01
subsystem: infra
tags: [esp32, arduino, firmware, bip39, slip0010, aes-256-cbc, mbedtls, nvs, ed25519]

# Dependency graph
requires: []
provides:
  - "BIP39 English wordlist (2048 words, PROGMEM) verified against bip39-2.2.2 crate"
  - "validateEntropy: chi-squared RNG test (threshold 350.0, 255 DOF)"
  - "generateMnemonic: 128-bit hw entropy -> SHA-256 checksum -> 12x11-bit BIP39 indices"
  - "mnemonicToSeed: PBKDF2-HMAC-SHA512, 2048 iterations, salt=mnemonic"
  - "slip10Derive: SLIP-0010 at m/44'/501'/0'/0' via HMAC-SHA512 chain"
  - "deriveEncKey: AES-256 key from device MAC via HMAC-SHA256(deadbolt-nvs-v1)"
  - "encryptSeed/decryptSeed: AES-256-CBC with IV[16]||ciphertext[48] NVS format"
  - "generate command: returns 12 BIP39 words JSON after 5s BOOT hold"
  - "reset command: nvs_flash_deinit + nvs_flash_erase + esp_restart"
  - "entropy_check command: runs validateEntropy and returns result"
  - "loadKeypair: migrates old plaintext privkey to encrypted enc_privkey on first load"
affects: [05-02, 05-03, 05-04, 05-05, rust-bridge, flutter-hardware]

# Tech tracking
tech-stack:
  added:
    - "mbedtls (bundled with arduino-esp32): SHA-256, HMAC-SHA512, PKCS5-PBKDF2, AES-256-CBC"
    - "bootloader_random.h (ESP-IDF, bundled): hardware entropy enable/disable"
    - "esp_mac.h (ESP-IDF, bundled): esp_efuse_mac_get_default for AES key derivation"
    - "nvs_flash.h (ESP-IDF, bundled): nvs_flash_deinit, nvs_flash_erase for factory reset"
  patterns:
    - "BIP39 C port: 132-bit stream (entropy[16] + hash[0]>>4), 11-bit index extraction"
    - "SLIP-0010: HMAC-SHA512 chain with hardened derivation (component + 0x80000000)"
    - "AES-256-CBC envelope: IV[16]||ciphertext[48] = 64 bytes for NVS storage"
    - "Migration guard: loadKeypair() re-encrypts old plaintext privkey on first boot"
    - "Command-driven key generation with physical 5s BOOT button confirmation"
    - "Firmware buffer zeroization: memset after every crypto use"

key-files:
  created:
    - "firmware/unruggable_esp32/bip39_wordlist.h: 2048-word BIP39 English PROGMEM array"
    - "firmware/unruggable_esp32/bip39.h: function declarations for all BIP39/SLIP-0010 ops"
    - "firmware/unruggable_esp32/bip39.cpp: validateEntropy, generateMnemonic, mnemonicToSeed, slip10Derive"
    - "firmware/unruggable_esp32/nvs_crypto.h: AES-256-CBC encrypt/decrypt declarations"
    - "firmware/unruggable_esp32/nvs_crypto.cpp: deriveEncKey, encryptSeed, decryptSeed"
  modified:
    - "firmware/unruggable_esp32/unruggable_esp32.ino: full rewrite with BIP39 commands"

key-decisions:
  - "bip39_wordlist.h verified word-for-word against bip39-2.2.2 crate (english.rs) - identical order and content"
  - "generate command sends generating status before button wait so Rust bridge knows to extend read timeout"
  - "loadKeypair is read-write (not read-only) to support migration: re-encrypts old plaintext key in-place"
  - "BOOT button timeout is 60 seconds for generate/reset before auto-cancel (not infinite wait)"
  - "Factory reset uses nvs_flash_deinit() + nvs_flash_erase() (default partition) not esp_partition_find_first pattern"
  - "setup() does NOT auto-generate keypair; device starts with no key until generate command received"

patterns-established:
  - "Firmware crypto: always bootloader_random_enable before sampling, disable after"
  - "Firmware secrets: memset every sensitive buffer immediately after last use"
  - "Serial protocol: send status:generating before blocking operations so host can extend timeout"

requirements-completed: [INFR-01, INFR-02, INFR-03, HWLT-04]

# Metrics
duration: 14min
completed: 2026-03-20
---

# Phase 5 Plan 01: ESP32 Firmware Rewrite Summary

**BIP39/SLIP-0010 hardware wallet firmware: verified entropy sampling, mnemonic generation, PBKDF2 seed derivation, AES-256-CBC NVS storage, and partition-level factory reset via mbedtls on Arduino ESP32-C3**

## Performance

- **Duration:** 14 min
- **Started:** 2026-03-20T08:29:11Z
- **Completed:** 2026-03-20T08:43:16Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Ported the full mnemonic.rs crypto pipeline to C (BIP39 generation, PBKDF2 seed, SLIP-0010 Ed25519 derivation) with word-for-word wordlist verification against the bip39-2.2.2 Rust crate
- Replaced plaintext NVS key storage with AES-256-CBC encryption keyed from device MAC via HMAC-SHA256, with automatic migration of pre-existing plaintext keys on first boot
- Added `generate`, `reset`, and `entropy_check` JSON serial commands with physical 5-second BOOT button confirmation gating; removed insecure idle button-hold regeneration

## Task Commits

Each task was committed atomically:

1. **Task 1: BIP39 wordlist, mnemonic generation, and SLIP-0010 derivation** - `51a6873` (feat)
2. **Task 2: NVS crypto module and firmware rewrite** - `f08c8a8` (feat)

## Files Created/Modified

- `firmware/unruggable_esp32/bip39_wordlist.h` - 2048-word BIP39 English wordlist in PROGMEM, verified against bip39-2.2.2 crate
- `firmware/unruggable_esp32/bip39.h` - Declares validateEntropy, generateMnemonic, mnemonicToSeed, slip10Derive
- `firmware/unruggable_esp32/bip39.cpp` - C port of mnemonic.rs algorithms using mbedtls; chi-squared entropy test; SLIP-0010 with path {44,501,0,0}
- `firmware/unruggable_esp32/nvs_crypto.h` - Declares deriveEncKey, encryptSeed, decryptSeed
- `firmware/unruggable_esp32/nvs_crypto.cpp` - AES-256-CBC with MAC-derived key; IV[16]||ciphertext[48]; PKCS7 padding
- `firmware/unruggable_esp32/unruggable_esp32.ino` - Complete firmware rewrite: BIP39 generation, encrypted NVS, new commands, migration path

## Decisions Made

- **Wordlist verified against crate:** bip39_wordlist.h word ordering confirmed identical to bip39-2.2.2 crate (english.rs) to ensure test vector `abandon×11 about` produces the same derivation result as Rust
- **generate sends "generating" status immediately:** Firmware responds before the 5-second wait so the Rust bridge can extend its read timeout (PBKDF2 takes ~1-3s on ESP32-C3)
- **loadKeypair is read-write:** Required for in-place migration of pre-BIP39 plaintext keys; prefs.begin("unruggable", false) not true
- **60-second BOOT button window:** Bounded wait prevents infinite hang if user walks away; cancelled with error response
- **nvs_flash_erase() (default partition) not esp_partition_find_first:** The simpler call erases the default "nvs" partition which is what Arduino Preferences uses; matches the RESEARCH.md NVS factory reset sequence
- **No auto-generate on boot:** Device starts with no key until `generate` command is explicitly sent; eliminates the old insecure random-key-on-first-boot behavior

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

- **Wordlist count mismatch (resolved):** Initial wordlist had only 1932 words. Resolved by diff against the official bip39-2.2.2 crate `english.rs` file to identify and add all 116 missing words (including `affair`, `bachelor`, `bonus`, `brass`, `bread`, `canoe`, `cattle`, `crop`, `economy`, `era`, `eyebrow`, `female`, `fold`, `garage`, `guess`, `harbor`, `hard`, `hotel`, `idea`, `identify`, `idle`, `illness`, `inch`, `include`, `inherit`, `initial`, `injury`, `inmate`, `label`, `labor`, `ladder`, `lady`, `lake`, `latin`, `leaf`, `leisure`, `light`, `lyrics`, `machine`, `mail`, `major`, `make`, `mass`, `matrix`, `measure`, `meat`, `mechanic`, `mirror`, `moment`, `myth`, `nation`, `net`, `network`, `neutral`, `nose`, `observe`, `obvious`, `occur`, `one`, `online`, `only`, `opinion`, `outer`, `output`, `oven`, `owner`, `patient`, `pattern`, `punch`, `raw`, `razor`, `rib`, `scare`, `school`, `science`, `seed`, `sick`, `side`, `skate`, `ski`, `soda`, `soft`, `sort`, `spell`, `spend`, `sport`, `spot`, `stool`, `style`, `surround`, `survey`, `suspect`, `swarm`, `system`, `talk`, `taste`, `tide`, `tiger`, `tissue`, `toddler`, `toe`, `true`, `unaware`, `unit`, `urge`, `usage`, `use`, `used`, `verb`, `verify`, `vessel`, `wash`, `wasp`, `whale`, `what`, `work`) — final count 2048, verified match.

## User Setup Required

None — this is firmware code only. No external services or environment variables required. Physical flashing to ESP32-C3 hardware is done via Arduino IDE (out of scope for this plan).

## Next Phase Readiness

- Firmware is ready for integration testing against the Rust bridge (Plan 02)
- The `rust/deadbolt_core/src/hardware/esp32_bridge.rs` already has the `generate`, `factory_reset`, and `check_entropy` methods and the `words` field in `Response` — firmware and bridge are aligned
- Test vector: `abandon` × 11 + `about` mnemonic should produce the same Ed25519 public key from both the Rust `derive_keypair` and the C `slip10Derive` — manual cross-check recommended before shipping

## Self-Check: PASSED

All files created and commits verified:
- FOUND: firmware/unruggable_esp32/bip39_wordlist.h
- FOUND: firmware/unruggable_esp32/bip39.h
- FOUND: firmware/unruggable_esp32/bip39.cpp
- FOUND: firmware/unruggable_esp32/nvs_crypto.h
- FOUND: firmware/unruggable_esp32/nvs_crypto.cpp
- FOUND: firmware/unruggable_esp32/unruggable_esp32.ino
- FOUND: .planning/phases/05-esp32-firmware-rewrite/05-01-SUMMARY.md
- FOUND: commit 51a6873 (Task 1)
- FOUND: commit f08c8a8 (Task 2)

---
*Phase: 05-esp32-firmware-rewrite*
*Completed: 2026-03-20*
