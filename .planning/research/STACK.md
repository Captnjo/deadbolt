# Stack Research

**Domain:** Solana wallet — auth, embedded agent API server, ESP32 firmware, guardrails engine
**Researched:** 2026-03-16
**Confidence:** MEDIUM (library versions verified via pub.dev and docs.rs; FFI patterns and guardrails design confirmed via community patterns and official discussions)

---

## Context: What Is Already Decided

The following are locked by the existing codebase. This document covers only the **new** additions.

| Technology | Version | Role |
|---|---|---|
| Flutter | 3.29+ | UI framework |
| Rust | stable | Crypto core |
| flutter_rust_bridge | 2.11.1 | FFI bridge |
| axum | server.rs exists | Agent HTTP server (partially built) |
| tokio | existing | Async runtime |

---

## Dimension 1: Flutter App Authentication

### Recommended: `local_auth` 3.0.1

**Purpose:** Password + Touch ID biometric unlock at app launch, idle timeout re-lock, and auth gate on sensitive operations (vault unlock, mnemonic reveal, sign tx, API key management).

**Why this, not alternatives:**
- It is the official Flutter team plugin, published under `flutter.dev` verified publisher
- Version 3.0.1 (published March 2026) supports macOS 10.15+ with endorsed macOS implementation via `local_auth_darwin`
- Uses Apple's `LocalAuthentication` framework under the hood — Touch ID on macOS, Face ID on iOS
- No special entitlements required; `LocalAuthentication` handles permissions automatically
- Provides clean `authenticate()` call with `biometricOnly: false` (the right default: tries Touch ID, falls back to system password dialog)
- Version 3.0.0 switched from `PlatformException` to `LocalAuthException` — cleaner error handling for auth-gating flows

**macOS specifics:**
- `local_auth_darwin` (the macOS/iOS implementation package) is auto-included
- Fallback to macOS login password works without extra setup when `biometricOnly: false`
- On developer machines without Touch ID (per PROJECT.md: "Testing on macOS desktop — no Touch ID on this machine"), the password fallback path exercises the same code

**What the app needs beyond `local_auth`:**

The lock/timeout state (idle timer, lock on foreground/background transitions) must live in Flutter, not the plugin. Use a top-level `AuthGuard` service that wraps `local_auth` and exposes a stream of `AuthState` (locked/unlocked). The existing vault unlock in Rust is already the source of truth — the Flutter auth gate is a UI protection layer on top, not a second encryption layer.

| Library | Version | Purpose |
|---|---|---|
| `local_auth` | 3.0.1 | Biometric + system password auth |
| `local_auth_darwin` | auto-included | macOS/iOS implementation |

**What NOT to use:**
- `biometric_storage` — combines auth + storage, couples concerns; the Rust vault already owns storage
- `flutter_screen_lock` — adds a custom PIN UI; the project uses a single app password, not a separate PIN
- `biometric_signature` — hardware-backed crypto signatures; unnecessary complexity, Rust owns all signing

---

## Dimension 2: Axum HTTP Server via FFI Bridge

### Pattern: Dedicated OS Thread + Single-Threaded Tokio Runtime, Exposed via FRB Functions

**Purpose:** Run the agent API server (localhost:9876) inside the Rust process, started and stopped by Flutter via `flutter_rust_bridge` FFI calls.

**Why this architecture:**
- The axum `server.rs` already exists in the repo. The work is exposing `start_server` / `stop_server` functions through FRB, not rewriting the server.
- flutter_rust_bridge v2 executes FFI calls on a thread pool and returns a Dart `Future` — async Rust functions work naturally
- Axum requires a Tokio runtime. FRB's internal runtime works for request/response functions, but a long-lived server needs its own runtime ownership

**Recommended runtime pattern:**

```rust
// In lib.rs / api.rs exposed via FRB
static SERVER_TX: OnceLock<tokio::sync::oneshot::Sender<()>> = OnceLock::new();

pub fn start_agent_server(port: u16) -> Result<(), String> {
    let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
    std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async move {
            // build axum router, bind to 127.0.0.1:port
            axum::serve(listener, app)
                .with_graceful_shutdown(async { shutdown_rx.await.ok(); })
                .await
                .unwrap();
        });
    });
    // store shutdown_tx in a global for stop_server
    Ok(())
}
```

This is the pattern recommended in the official axum discussion thread (tokio-rs/axum#2501). The dedicated OS thread ensures the server's Tokio runtime is completely isolated from FRB's internal thread pool — no runtime conflicts.

**Why NOT `tokio::spawn` from FRB context:**
FRB manages its own Tokio executor. Spawning from within an FRB call works but creates a dependency on FRB's runtime lifetime. The dedicated thread pattern is more robust and matches the existing `server.rs` structure.

**Versions required:**

| Crate | Version | Purpose | Why |
|---|---|---|---|
| `axum` | 0.8.x | HTTP router/server | Current stable (Jan 2025 release); new `{param}` route syntax, native async traits |
| `tokio` | 1.x (multi-thread or current-thread) | Async runtime | Required by axum; FRB already depends on tokio 1.x |
| `tower-http` | 0.6.x | Middleware (CORS, auth headers, logging) | axum 0.8 depends on `^0.6`; fully compatible |
| `tower` | 0.5.x | Service abstraction | Axum middleware layer system |

**Bearer token auth (the `db_` prefix API keys):**

Do not use a JWT library — the tokens are simple random bearer tokens stored in the Rust vault. Use a custom Tower middleware layer:

```rust
// Custom middleware reads Authorization: Bearer <token>
// validates against stored hashed tokens in vault
// returns 401 if missing/invalid
```

`tower-http`'s `ValidateRequestHeaderLayer::bearer()` is compile-time only (static token). Use `axum::middleware::from_fn` with a closure that calls into the vault for runtime token validation.

**What NOT to use:**
- `warp` — different paradigm; axum is already chosen and server.rs exists
- `actix-web` — not composable with Tower; incompatible with the existing code
- `rinf` (alternative FRB) — project already uses flutter_rust_bridge v2; switching would be a rewrite

---

## Dimension 3: ESP32-C3 BIP39 Mnemonic Generation in Rust

### Recommended: `bip39` 2.2.2 + `esp-hal` 1.0.0 + `esp-alloc` for heap

**Purpose:** Rewrite ESP32-C3 firmware to generate BIP39 mnemonics on-device, expose via USB-CDC serial (JSON protocol), and derive Ed25519 keys from the seed — replacing the current Arduino C firmware.

**Why `bip39` 2.2.2:**
- Current stable release (December 2025)
- Explicitly supports `no_std`: "This crate supports Rust v1.41.1 and up and works with `no_std`"
- Use with `default-features = false, features = ["alloc"]` to eliminate std dependency while keeping heap allocation
- `zeroize` feature available — use it to wipe mnemonic bytes after key derivation (security requirement)
- Only `rand` feature needed for generation; disable all languages except English to minimize flash usage

**Cargo.toml for ESP32-C3:**
```toml
[dependencies]
bip39 = { version = "2.2.2", default-features = false, features = ["alloc", "rand"] }
esp-alloc = "0.6"          # heap allocator for no_std alloc
esp-hal = { version = "1.0.0", features = ["unstable"] }
getrandom = { version = "0.2", features = ["custom"] }  # custom RNG backend
```

**Why `esp-hal` 1.0.0:**
- Official Espressif-maintained no_std HAL (released October 2025)
- Full ESP32-C3 support (RISC-V target, upstream Rust toolchain — no Xtensa fork needed)
- Stable APIs for GPIO, UART, SPI, I2C
- USB-CDC Serial/JTAG peripheral available on ESP32-C3 (GPIO18/19) — this is how the existing serial protocol works

**Caveat on esp-hal stability:**
esp-hal 1.0.0-beta.0 stabilized only four drivers (GPIO, UART, SPI, I2C). Most complex features require `features = ["unstable"]` in Cargo.toml. USB Serial/JTAG is likely under `unstable`. This is acceptable — the project accepts beta-quality firmware.

**Why no_std over std+esp-idf:**
- The ESP32-C3 has ~384KB RAM. The std+esp-idf approach pulls in FreeRTOS and a full newlib environment, consuming significantly more RAM and flash.
- The existing firmware is already bare-metal (Arduino C). Staying no_std keeps the footprint small.
- BIP39 mnemonic tables (English wordlist) are ~7KB in flash — acceptable on 16MB flash

**RNG for mnemonic generation:**
The `bip39` `rand` feature requires a random number source. On ESP32-C3, use the hardware TRNG via `esp-hal`'s `Rng` peripheral. Provide a `getrandom` custom implementation that reads from `esp_hal::Rng`.

**Serial protocol:**
The existing JSON-over-serial protocol is correct. Keep it. The new firmware adds:
- `generate_mnemonic` command → returns 24-word mnemonic (display only, never stored on host)
- `confirm_mnemonic` + verification step → derives seed, derives keypair, stores in secure flash partition

| Crate | Version | Purpose |
|---|---|---|
| `bip39` | 2.2.2 | BIP39 mnemonic generation and seed derivation |
| `esp-hal` | 1.0.0 | No_std HAL for ESP32-C3 (UART, USB CDC, RNG, Flash) |
| `esp-alloc` | 0.6 | Heap allocator (needed for `alloc` feature in bip39) |
| `getrandom` | 0.2 | RNG abstraction (custom backend pointing to esp-hal Rng) |

**What NOT to use:**
- `bip0039` (0.14.0) — less maintained alternative; `rust-bitcoin/bip39` is the canonical crate
- `tiny-bip39` — older fork; maintenance unclear; `bip39` 2.x is the successor
- `std` + esp-idf-sys — RAM overhead too high; no_std is correct for this device
- `bip32` crate's built-in BIP39 — bip32 crate bundles BIP39 support but the standalone `bip39` crate is more flexible for this use case

---

## Dimension 4: Guardrails / Rate-Limiting for Transaction Signing

### Recommended: Custom Rust State Machine + `governor` 0.10.4 for per-key rate limiting

**Purpose:** Per-transaction limits (SOL, USD), daily limits (count, USD), cooldowns, token whitelist, program whitelist — applying to both agent-submitted and manual transactions.

**Architecture decision: Business logic, not HTTP rate limiting**

The guardrails here are **transaction signing guardrails**, not API request rate limiting. They need to:
- Track cumulative spend across a rolling 24-hour window
- Compare against USD limits (requires price feed integration)
- Check token and program whitelists
- Persist state across app restarts (daily limits must survive restarts)
- Return specific error messages to the agent ("daily limit exceeded: $4,800/$5,000")

This is fundamentally different from HTTP rate limiting (which counts requests, not dollar amounts). Build a custom `GuardrailsEngine` struct in Rust.

**Custom `GuardrailsEngine` design:**
```rust
pub struct GuardrailsEngine {
    config: GuardrailsConfig,           // per-tx limits, daily limits, whitelists
    daily_tracker: Mutex<DailyTracker>, // rolling 24h spend tracker
}

struct DailyTracker {
    reset_at: SystemTime,   // next midnight reset
    tx_count: u32,
    usd_spent: f64,
}
```

Store `GuardrailsConfig` in the existing Rust vault (same secure storage backend). Persist `DailyTracker` to a sidecar file (not the vault — it changes on every transaction, vault is for secrets).

**For API request rate limiting (protecting the HTTP endpoints):**
Use `governor` 0.10.4 as middleware. This protects against agent bugs that flood the endpoint — not the transaction guardrails, but a safety net.

| Crate | Version | Purpose |
|---|---|---|
| `governor` | 0.10.4 | HTTP endpoint rate limiting (requests/sec, not dollars) |
| Custom `GuardrailsEngine` | — | Transaction spend limits, whitelists, cooldowns |

**Why `governor` over `tower-governor`:**
- `governor` is the foundational GCRA crate — lock-free, 64-bit atomic state, 10x faster than Mutex-based alternatives
- `tower-governor` wraps `governor` for Tower/axum — use it for the HTTP layer
- `tower_governor` version is ~0.3.x but the underlying `governor` 0.10.4 is what matters

**tower-governor for HTTP layer:**
```toml
tower-governor = { version = "0.3", features = ["axum"] }
```
Apply as a global router layer for `/intent` and `/sign` endpoints. Key extractor: bearer token (each API key gets its own quota bucket).

**Cooldown pattern:**
Governor does not natively support "no more than 3 transactions in 10 minutes with a 5-minute cooldown after each." This requires custom logic in `GuardrailsEngine`. Implement as: `last_tx_at: Option<SystemTime>` + `cooldown_seconds: u64` in the tracker.

**Bypass with app password:**
Store a `bypass_until: Option<SystemTime>` in the in-memory `GuardrailsEngine`. When the user authenticates with app password, set `bypass_until = now + timeout`. Check this in `check_guardrails()` before evaluating limits.

**What NOT to use:**
- Redis-backed rate limiting — this is a localhost app, no external services
- `basic-axum-rate-limit` — token bucket for request counting only; not appropriate for dollar-amount limits
- Storing guardrails state in SQLite — overkill for this scope; a JSON sidecar file is sufficient

---

## Supporting Libraries (Already in Existing Codebase)

These are confirmed existing; listed here for dependency compatibility reference:

| Crate | Version | Role |
|---|---|---|
| `serde` + `serde_json` | existing | JSON serialization for intent/response payloads |
| `tokio` | 1.x | Async runtime |
| `flutter_rust_bridge` | 2.11.1 | FFI bridge |

---

## Installation Summary

### Flutter (pubspec.yaml additions)

```yaml
dependencies:
  local_auth: ^3.0.1
```

### Rust core (Cargo.toml additions)

```toml
[dependencies]
axum = "0.8"
tower = "0.5"
tower-http = { version = "0.6", features = ["auth", "trace"] }
tower-governor = { version = "0.3", features = ["axum"] }
governor = "0.10"
tokio = { version = "1", features = ["rt", "rt-multi-thread", "macros", "sync"] }
```

### ESP32-C3 firmware (separate Cargo.toml)

```toml
[dependencies]
bip39 = { version = "2.2.2", default-features = false, features = ["alloc", "rand"] }
esp-hal = { version = "1.0.0", features = ["unstable"] }
esp-alloc = "0.6"
getrandom = { version = "0.2", features = ["custom"] }
serde = { version = "1", default-features = false, features = ["derive"] }
serde-json-core = "0.6"  # no_std JSON for serial protocol responses
```

---

## Alternatives Considered

| Recommended | Alternative | Why Not |
|---|---|---|
| `local_auth` 3.0.1 | `biometric_storage` | Combines auth + storage; Rust vault already owns storage; coupling violation |
| `local_auth` 3.0.1 | `flutter_screen_lock` | Custom PIN UI; project uses single app password, not a PIN screen |
| Dedicated OS thread for axum | `tokio::spawn` from FRB | FRB runtime ownership; dedicated thread is fully isolated |
| `bip39` 2.2.2 | `bip0039` 0.14 | Less maintained; rust-bitcoin is the canonical org |
| Custom `GuardrailsEngine` | `governor` for dollar limits | GCRA is request-rate, not dollar-amount; domain logic requires custom state |
| `governor` for HTTP layer | Redis + sliding window | No infrastructure; localhost app |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|---|---|---|
| `biometric_storage` | Couples auth + key storage; Rust vault owns secrets | `local_auth` (auth only) |
| `actix-web` | Not Tower-composable; incompatible with existing axum code | `axum` 0.8 (already chosen) |
| `tower-http` `ValidateRequestHeaderLayer::bearer()` with static string | Compile-time token only; can't validate runtime-issued API keys | Custom `axum::middleware::from_fn` with vault lookup |
| `tiny-bip39` | Older fork; maintenance status unclear | `bip39` 2.2.2 (rust-bitcoin maintained) |
| std + esp-idf on ESP32-C3 | FreeRTOS + newlib overhead on 384KB RAM device | `esp-hal` no_std (smaller footprint) |
| SQLite for guardrails state | Overkill; adds binary size; state is simple counters + timestamps | In-memory struct + JSON sidecar file |

---

## Version Compatibility Matrix

| Package | Compatible With | Notes |
|---|---|---|
| `axum` 0.8.x | `tower-http` ^0.6, `tokio` ^1, `tower` ^0.5 | axum 0.8 requires tower-http 0.6; both 0.7.x and 0.6.x tower-http are incompatible with 0.8 |
| `flutter_rust_bridge` 2.11.1 | `tokio` 1.x | FRB v2 uses tokio internally; don't create a second multi-thread runtime in same process |
| `local_auth` 3.0.1 | Flutter 3.29+, Dart 3.7+ | v3.0.0 dropped support for Flutter < 3.29; PROJECT.md specifies Flutter 3.11+ — **check actual Flutter version in pubspec.yaml before upgrading** |
| `bip39` 2.2.2 | Rust 1.41.1+, no_std+alloc | Requires `esp-alloc` heap setup before any `alloc` use on ESP32-C3 |
| `esp-hal` 1.0.0 | Rust stable 1.85.0+ (RISC-V upstream toolchain) | ESP32-C3 is RISC-V; no Xtensa fork needed unlike original ESP32 |
| `governor` 0.10.4 | `tower-governor` 0.3 | tower-governor wraps governor; use same governor version |

---

## Stack Patterns by Variant

**If Touch ID is unavailable on test machine (current situation):**
- `local_auth` gracefully falls back to macOS password dialog when `biometricOnly: false`
- `getAvailableBiometrics()` returns empty list; `authenticate()` still works via password
- Test the full auth flow normally; biometric path will be verified on hardware with Touch ID

**If the existing axum server.rs has Tokio runtime issues:**
- Check whether `server.rs` uses `#[tokio::main]` — that attribute creates a new runtime, which conflicts with FRB's runtime
- Remove `#[tokio::main]` and use the dedicated-thread pattern above instead
- FRB already provides a tokio runtime; don't create a second multi-thread runtime

**If ESP32-C3 runs out of heap with bip39:**
- English wordlist is the only required language feature
- Disable `unicode-normalization` feature (not needed for English-only BIP39)
- The mnemonic is generated and immediately converted to a seed; it doesn't need to persist on heap
- 32KB heap allocation via `esp-alloc` should be sufficient

---

## Sources

- pub.dev/packages/local_auth — version 3.0.1 confirmed, macOS 10.15+ support, Flutter 3.29+ minimum (HIGH confidence)
- pub.dev/packages/local_auth/changelog — v3.0.0 breaking changes: `LocalAuthException`, new parameter API (HIGH confidence)
- tokio.rs/blog/2025-01-01-announcing-axum-0-8-0 — axum 0.8 release, new route syntax, async trait changes (HIGH confidence)
- github.com/tokio-rs/axum/discussions/2501 — dedicated OS thread pattern for axum in non-async contexts (MEDIUM confidence)
- docs.rs bip39 2.2.2 — version confirmed, no_std support confirmed, feature flags documented (HIGH confidence)
- lib.rs/crates/bip39 — December 2025 release date confirmed (HIGH confidence)
- github.com/esp-rs/esp-hal — 1.0.0 release October 2025, ESP32-C3 supported, beta status (HIGH confidence)
- developer.espressif.com/blog/2025/02/rust-esp-hal-beta — beta caveats, `unstable` feature gate (HIGH confidence)
- docs.rs/governor — version 0.10.4, GCRA algorithm, per-key rate limiting, in-memory (HIGH confidence)
- github.com/benwis/tower-governor — tower-governor 0.3 wraps governor for axum (MEDIUM confidence — version from README only)

---

## Open Questions / Flags for Phase Research

1. **Flutter version constraint**: `local_auth` 3.0.1 requires Flutter 3.29+ / Dart 3.7+. PROJECT.md states Flutter 3.11+. Before using `local_auth` 3.x, verify actual `flutter` SDK version in pubspec.yaml. If below 3.29, use `local_auth` 2.3.0 (last 2.x, added endorsed macOS support) instead.

2. **Existing server.rs compatibility with axum 0.8**: The route syntax changed (`/:id` → `/{id}`). Verify which axum version `server.rs` currently targets before assuming 0.8 compatibility.

3. **ESP32-C3 USB-CDC under `unstable`**: The USB Serial/JTAG peripheral in esp-hal 1.0.0 is likely behind the `unstable` feature gate. Verify in esp-hal docs/examples before firmware sprint begins.

4. **DailyTracker persistence format**: JSON sidecar file is recommended, but the file location must be platform-appropriate (macOS: `~/Library/Application Support/Deadbolt/`). Verify the existing Rust storage layer's path logic covers this.

---
*Stack research for: Deadbolt — auth, agent API, ESP32 firmware, guardrails*
*Researched: 2026-03-16*
