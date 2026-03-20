# Phase 5: ESP32 Firmware Rewrite - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Rewrite the ESP32 firmware to generate BIP39 mnemonics from verified hardware entropy, derive Ed25519 keypairs via SLIP-0010, store seeds encrypted on-device, and guide the user through mnemonic backup in the Flutter app. Add auto-connect, pubkey verification on reconnect, and a dedicated Hardware Wallet sidebar entry.

</domain>

<decisions>
## Implementation Decisions

### Mnemonic backup flow
- 12-word mnemonic (not 24)
- All 12 words displayed on a single screen, numbered
- Verification quiz after display: user selects correct word for 3-4 random positions before proceeding
- Screenshots blocked on the mnemonic screen (FLAG_SECURE / platform screenshot prevention)
- Mnemonic shown exactly once during setup — after quiz, it's never retrievable from the app

### Firmware architecture
- **All crypto runs on ESP32** — BIP39 generation, SLIP-0010 derivation, seed storage. Private key never leaves the device.
- ESP32 generates mnemonic from its own hardware entropy, sends words to host for display only
- Entropy: `esp_fill_random()` (true hardware RNG on ESP32-C3) with runtime randomness test at boot; firmware refuses to generate if test fails (LED error pattern)
- Seed encrypted with AES-256 using a key derived from ESP32-C3's unique eFuse ID (hardware AES acceleration available)
- Factory reset: `nvs_flash_erase_partition()` erases entire NVS partition (not soft-delete)
- Factory reset trigger: app sends reset command + user must hold BOOT button for 5 seconds to confirm (two-factor: software + physical)
- Derivation path: `m/44'/501'/0'/0'` (Solana standard, single key for v1)
- Firmware stays on Arduino framework (no migration to ESP-IDF)

### Device lifecycle
- Auto-connect: background USB port scan on app launch, silent connect if registered device found (no user prompt)
- Pubkey mismatch on reconnect: persistent warning banner + block all signing until resolved; offer re-register or disconnect
- Unexpected disconnect: toast notification "Hardware wallet disconnected", pending signing fails with clear error, sidebar updates
- Poll rate: every 5 seconds for connection status

### Hardware Wallet sidebar
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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Firmware
- `firmware/unruggable_esp32/unruggable_esp32.ino` — Current ESP32 firmware: JSON command protocol, Ed25519 signing, LED patterns, button confirmation
- `rust/deadbolt_core/src/crypto/mnemonic.rs` — Reference BIP39 + SLIP-0010 implementation in Rust (port logic to C/Arduino)

### Hardware bridge
- `rust/deadbolt_core/src/hardware/esp32_bridge.rs` — Serial communication protocol, chunked writes, JSON parsing
- `rust/deadbolt_core/src/hardware/esp32_signer.rs` — TransactionSigner trait implementation
- `rust/deadbolt_core/src/hardware/esp32_detector.rs` — USB VID/PID detection (Espressif, CP210x, CH340)
- `rust/deadbolt_bridge/src/api/hardware.rs` — FRB bridge: scanHardwareWallets, connectHardwareWallet

### Flutter UI
- `lib/features/wallet/connect_hardware_screen.dart` — Current hardware connection UI (port scanning, registration)
- `lib/shared/widgets/wallet_drawer.dart` — Sidebar with hardware wallet indicator (lines 168-172)
- `lib/providers/wallet_provider.dart` — hwDetectedProvider, wallet state management
- `lib/routing/app_router.dart` — Route `/wallets/hardware` (line 143-147)
- `lib/features/lock/auth_challenge_dialog.dart` — Reusable password challenge pattern

### Models
- `rust/deadbolt_core/src/models/wallet.rs` — WalletSource::Hardware enum, wallet config structure

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `mnemonic.rs`: Full BIP39 + SLIP-0010 implementation — reference for C port (generation, validation, derivation, quiz word generation)
- `esp32_bridge.rs`: Serial protocol already handles JSON commands, chunked writes, boot banner skipping
- `esp32_detector.rs`: VID/PID scanning for Espressif, CP210x, CH340 devices
- `auth_challenge_dialog.dart`: Password challenge widget — reuse for factory reset confirmation
- `connect_hardware_screen.dart`: Port scanning UI with 3-second poll — adapt for 5-second poll and auto-connect

### Established Patterns
- JSON line-delimited serial protocol: `{"cmd":"..."}` → `{"status":"..."}` with newline delimiters
- FRB bridge pattern: Rust function → generated Dart FFI binding → Flutter provider
- Sidebar navigation: sidebar entries defined in `wallet_drawer.dart`, routes in `app_router.dart`
- Hardware wallet signing: `sign_serialized_transaction_hardware()` in `sign.rs` already wired

### Integration Points
- New firmware commands needed: `generate` (trigger BIP39 generation), `mnemonic` (retrieve words), `reset` (factory reset), `entropy_check` (verify RNG)
- New Rust bridge functions: `generateHardwareKeypair()`, `getHardwareMnemonic()`, `factoryResetHardware()`
- New Flutter screens: mnemonic display, verification quiz, device dashboard
- Sidebar: add permanent "Hardware Wallet" entry alongside existing nav items

</code_context>

<specifics>
## Specific Ideas

- Factory reset requires both app command AND physical button hold (5 seconds) — two-factor confirmation prevents accidental or remote wipe
- Mnemonic verification quiz should use `random_words()` from mnemonic.rs as distractors (already implemented in Rust, port concept to quiz UI)
- ESP32-C3's hardware AES acceleration should be used for seed encryption — much faster than software AES

</specifics>

<deferred>
## Deferred Ideas

- **Multiple pubkeys per seed** (HWLT-V2-01) — SLIP-0010 derivation path indices (`m/44'/501'/N'/0'`). Architecture supports it since we're building the derivation on-device; future phase just changes the index.
- **Multi-device support** — Connect and manage multiple ESP32 devices simultaneously, each with their own wallet addresses. Requires device registry and switching logic.
- **Firmware flashing through the app** — Bundle esptool, detect ESP32 in bootloader mode, flash Deadbolt firmware over USB serial. Separate phase due to complexity. Approach decided: esptool + serial bootloader protocol.
- **HD wallet derivation from mnemonic** — Support multiple software wallet addresses from one seed phrase (noted during Phase 4 testing).

</deferred>

---

*Phase: 05-esp32-firmware-rewrite*
*Context gathered: 2026-03-20*
