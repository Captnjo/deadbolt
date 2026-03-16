# Architecture Research

**Domain:** Embedded Rust/Flutter wallet with agent API and hardware signer
**Researched:** 2026-03-16
**Confidence:** HIGH (based on direct codebase inspection + FRB v2 docs)

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         FLUTTER UI LAYER                             │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │
│  │  Auth Gate   │  │ Agent Prompt │  │  Guardrails  │               │
│  │  (Riverpod)  │  │  Overlay /   │  │  Settings UI │               │
│  │              │  │  Queue List  │  │              │               │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘               │
│         │                 │                 │                        │
│  ┌──────┴─────────────────┴─────────────────┴──────────────────┐    │
│  │              Auth Provider (Riverpod)                        │    │
│  │  session state | idle timer | biometric/password gate        │    │
│  └──────┬───────────────────────────────────────────────────────┘    │
└─────────┼───────────────────────────────────────────────────────────┘
          │ flutter_rust_bridge v2 FFI (sync + async + StreamSink)
┌─────────┼───────────────────────────────────────────────────────────┐
│         │         RUST BRIDGE LAYER (deadbolt_bridge)               │
│  ┌──────┴────────────────────────────────────────────────────────┐  │
│  │  api/agent.rs   — start/stop server, approve/reject intent    │  │
│  │  api/wallet.rs  — unlock/lock, create/import, get_mnemonic    │  │
│  │  api/sign.rs    — sign_serialized_transaction (sw + hw)       │  │
│  │  api/hardware.rs — scan ports, connect_hardware_wallet        │  │
│  └──────┬────────────────────────────────────────────────────────┘  │
└─────────┼───────────────────────────────────────────────────────────┘
          │ direct Rust function calls (same process)
┌─────────┼───────────────────────────────────────────────────────────┐
│         │         RUST CORE LAYER (deadbolt_core)                   │
│                                                                      │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌─────────────┐   │
│  │ agent/     │  │ crypto/    │  │ hardware/  │  │ solana/     │   │
│  │ server.rs  │  │ vault.rs   │  │ esp32_     │  │ transaction │   │
│  │ auth.rs    │  │ mnemonic.rs│  │ bridge.rs  │  │ builder.rs  │   │
│  │ guardrails │  │ signer.rs  │  │ esp32_     │  │             │   │
│  │ intent.rs  │  │            │  │ signer.rs  │  │             │   │
│  └────────────┘  └────────────┘  └────────────┘  └─────────────┘   │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  models/ — WalletManager, AppConfig, GuardrailsConfig          │  │
│  │  storage/ — KeychainStorage (macOS), DPAPI (Win), SecretSvc    │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────┬──────────────────────────────┘
                                        │
             ┌──────────────────────────┴───────────────────────┐
             │                                                   │
      ┌──────┴───────┐                               ┌──────────┴──────────┐
      │  localhost   │                               │  USB Serial         │
      │  :9876 (HTTP)│                               │  /dev/cu.*          │
      │  axum server │                               │  115200 baud        │
      └──────┬───────┘                               └──────────┬──────────┘
             │ Bearer token                                      │ JSON lines
      ┌──────┴───────┐                               ┌──────────┴──────────┐
      │  AI Agent    │                               │  ESP32-C3 Firmware  │
      │  (curl/http) │                               │  (BIP39 + Ed25519)  │
      └──────────────┘                               └─────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|---------------|----------------|
| Auth Provider (Dart) | Session state, idle timer, biometric/password gate, lock-on-timeout | Riverpod StateNotifier |
| Auth Gate (Dart) | Intercept navigation/operations requiring auth, show unlock modal | Riverpod consumer widget |
| Agent Prompt (Dart) | Display pending intents, show simulation results, approve/reject UI | Overlay + queue list |
| agent/server.rs | axum HTTP server, intent queue, mpsc channel to Dart | Rust, tokio::spawn |
| agent/auth.rs | Bearer token middleware, token validation against AppConfig | axum middleware |
| agent/guardrails.rs | Per-tx/daily limits, cooldowns, whitelist checks | GuardrailsEngine struct |
| agent/intent.rs | Intent type/status lifecycle, uuid, timestamps | Pure Rust data types |
| api/agent.rs (bridge) | FRB-exposed functions: start_server, approve, reject; StreamSink for events | deadbolt_bridge |
| crypto/vault.rs | ChaCha20-Poly1305 encryption, scrypt KDF | deadbolt_core |
| crypto/signer.rs | Ed25519 signing, TransactionSigner trait | deadbolt_core |
| models/wallet_manager.rs | Wallet CRUD, active wallet, unlock/lock session | deadbolt_core |
| storage/keychain.rs | macOS Keychain, Windows DPAPI, Linux secret-service | Platform-specific |
| hardware/esp32_bridge.rs | Serial port driver, JSON line protocol, chunked writes | deadbolt_core |
| ESP32 firmware | BIP39 generation, PBKDF2 seed derivation, Ed25519 signing, NVS storage | Arduino C / ESP-IDF |

## Recommended Project Structure

```
rust/
├── deadbolt_core/src/
│   ├── agent/
│   │   ├── mod.rs
│   │   ├── server.rs        # AgentServer struct, axum router (exists)
│   │   ├── auth.rs          # Bearer token middleware (exists)
│   │   ├── guardrails.rs    # GuardrailsEngine (exists)
│   │   └── intent.rs        # Intent/IntentType/IntentStatus (exists)
│   ├── crypto/
│   │   ├── vault.rs         # ChaCha20-Poly1305 + scrypt (exists)
│   │   ├── mnemonic.rs      # BIP39 (exists)
│   │   └── signer.rs        # Ed25519 + TransactionSigner trait (exists)
│   ├── hardware/
│   │   ├── esp32_bridge.rs  # Serial driver (exists)
│   │   └── esp32_signer.rs  # Impl TransactionSigner for ESP32 (exists)
│   └── models/
│       ├── config.rs        # AppConfig, GuardrailsConfig (needs auth fields)
│       └── wallet_manager.rs # unlock/lock/session (needs auth password gate)
│
├── deadbolt_bridge/src/api/
│   ├── agent.rs             # NEW: FRB-exposed agent server control + StreamSink
│   ├── wallet.rs            # unlock_wallet etc (exists, needs password param)
│   ├── sign.rs              # sign_serialized_transaction (exists)
│   └── hardware.rs          # scan_hardware_wallets, connect (exists)
│
firmware/
└── unruggable_esp32/
    └── unruggable_esp32.ino # Rewrite: add BIP39 + PBKDF2 + SLIP-0010

lib/
├── features/
│   ├── agent/               # NEW feature directory
│   │   ├── agent_provider.dart
│   │   ├── agent_prompt_overlay.dart
│   │   └── agent_settings_screen.dart
│   └── settings/
│       └── security/        # NEW: auth settings (timeout, biometric toggle)
├── providers/
│   └── auth_provider.dart   # NEW: session/idle timer/lock state
└── shared/
    └── widgets/
        └── auth_gate.dart   # NEW: wrap sensitive screens/ops
```

## Architectural Patterns

### Pattern 1: StreamSink for Rust-to-Dart Event Push

**What:** A single FRB function accepts a `StreamSink<IntentEventDto>` parameter. FRB translates this to a `Stream<IntentEventDto>` on the Dart side. The Rust `AgentServer` holds the `mpsc::UnboundedSender<Intent>` and bridges it to the `StreamSink` via a bridge function that runs for the app lifetime.

**When to use:** Any time the Rust layer needs to push unsolicited events to Dart — agent intents arriving, signing status updates, ESP32 connection events.

**Trade-offs:** Simple and low-overhead. The `StreamSink` is held in a static after the bridge function returns; FRB v2 explicitly supports this. The alternative (Dart polling an FFI function) creates unnecessary CPU churn and latency.

**Example:**
```rust
// In api/agent.rs (bridge crate)
pub async fn subscribe_agent_events(sink: StreamSink<IntentEventDto>) -> Result<()> {
    // Start server if not running; store sink in static or OnceLock
    // Spawn a task that bridges mpsc::Receiver<Intent> -> sink.add(...)
    tokio::spawn(async move {
        while let Some(intent) = rx.recv().await {
            sink.add(IntentEventDto::from(intent));
        }
    });
    Ok(())
}
```

```dart
// In agent_provider.dart
final stream = subscribeAgentEvents();
stream.listen((event) {
    ref.read(agentQueueProvider.notifier).add(event);
});
```

### Pattern 2: Tokio Runtime Sharing Between FRB and axum

**What:** FRB v2 creates a multi-threaded tokio runtime internally. The `AgentServer::start()` function calls `tokio::net::TcpListener::bind()` and `axum::serve(...)` with `tokio::spawn`. Since FRB async functions run on this same runtime, the axum server lives on FRB's runtime — no separate runtime needed and no "cannot start runtime from within runtime" error.

**When to use:** Always. The key rule: `AgentServer::start()` must be called from an `async fn` exposed via FRB (not a sync fn), so it executes inside FRB's tokio context. Do not call `Runtime::new().block_on(...)` from bridge functions.

**Trade-offs:** FRB's runtime is multi-threaded (`tokio::runtime::Builder::new_multi_thread`), which is required for axum. Single-threaded runtimes will not work with axum's server accept loop. This is the correct default behavior in FRB v2.

**Example:**
```rust
// Correct: async fn, runs on FRB's tokio runtime
pub async fn start_agent_server(
    port: u16,
    tokens: Vec<String>,
    sink: StreamSink<IntentEventDto>,
) -> Result<(), String> {
    let (server, rx) = AgentServer::start(port, tokens, ...).await
        .map_err(|e| e.to_string())?;
    // Store server handle in OnceLock/Mutex static
    // Bridge rx -> sink in a spawned task
    Ok(())
}
```

### Pattern 3: App Password as the Single Auth Layer in Rust

**What:** App password authentication is handled entirely in Rust. `WalletManager::unlock()` currently reads from Keychain without a user password. The new pattern adds a `verify_app_password(password: &str) -> Result<()>` function to the bridge that: (1) runs scrypt with the stored hash, (2) opens a session token stored in a `Mutex<Option<SessionToken>>` in the global WalletManager or a new `AuthState` struct. Flutter checks the session token validity before calling any sensitive operation.

**When to use:** All sensitive ops: unlock vault, reveal mnemonic, create/revoke API key, sign transaction, change guardrails.

**Trade-offs:** Keeping auth in Rust means the password never passes through Dart as plaintext for longer than the FFI call. The `zeroize` crate is already a dependency and can zero the password bytes. Biometrics are Flutter-layer only (via `local_auth` on macOS) and call `unlock_with_biometric()` on the bridge which reuses an existing valid session or re-establishes one using a stored hash.

**Example:**
```rust
// New function in api/wallet.rs
pub fn verify_app_password(password: String) -> Result<(), String> {
    let mgr = manager().read().map_err(|e| e.to_string())?;
    mgr.verify_password(password.as_bytes())
        .map_err(|e| e.to_string())?;
    // Establish session
    SESSION.lock().unwrap().replace(SessionToken::new());
    Ok(())
}

pub fn check_session_valid() -> bool {
    SESSION.lock().unwrap()
        .as_ref()
        .map(|s| !s.is_expired())
        .unwrap_or(false)
}
```

### Pattern 4: ESP32 BIP39 Firmware Architecture

**What:** The firmware rewrite adds: (1) BIP39 wordlist stored in flash (progmem), (2) PBKDF2-HMAC-SHA512 seed derivation (2048 iterations), (3) SLIP-0010 Ed25519 key derivation from seed, (4) NVS storage for the 64-byte seed (not the derived key), (5) mnemonic display via serial for backup flow.

**When to use:** New keypair generation from the app. Existing raw keypair generation (`{"cmd":"generate"}`) is preserved for backward compatibility.

**Trade-offs:** PBKDF2-HMAC-SHA512 with 2048 iterations is computationally expensive on ESP32-C3 (~5-15 seconds at 160 MHz). This is acceptable for a one-time keygen operation. The wordlist (~85KB for 2048 words at ~41 bytes/word) must live in flash (PROGMEM/DRAM mapped), not stack. Serial protocol adds new commands: `{"cmd":"generate_bip39"}`, `{"cmd":"get_mnemonic"}`, `{"cmd":"derive_pubkey", "path":"m/44'/501'/0'/0'"}`.

**Example (new serial commands):**
```
→ {"cmd":"generate_bip39"}
← {"status":"ok","pubkey":"<hex>","address":"<base58>"}

→ {"cmd":"get_mnemonic"}
← {"status":"ok","words":["word1","word2",...,"word24"]}

→ {"cmd":"derive_pubkey","path":"m/44'/501'/0'/0'"}
← {"status":"ok","pubkey":"<hex>","address":"<base58>"}
```

## Data Flow

### Agent Signing Flow (primary flow)

```
AI Agent
    │ POST /intent {"type":"send_sol","to":"...","lamports":1000000000}
    │ Authorization: Bearer db_xxxxx
    ▼
axum server (localhost:9876)
    │ auth_middleware: validate token against AppState.api_tokens
    │ GuardrailsEngine.check(): per-tx limits, daily limits, cooldowns
    │ Intent::new() → Pending status, uuid
    │ mpsc_sender.send(intent.clone())
    │
    ├──→ HTTP 201 {"id":"uuid","status":"pending"}  (back to agent)
    │
    ▼
mpsc::UnboundedReceiver<Intent>  (bridge task)
    │ receives intent
    ▼
StreamSink<IntentEventDto>  (FRB rust2dart)
    │
    ▼
Dart Stream<IntentEventDto>  (agent_provider.dart)
    │ ref.read(agentQueueProvider.notifier).add(event)
    │ trigger background simulation (Helius RPC)
    ▼
AgentPromptOverlay (Flutter)
    │ User sees: intent type, amount, destination, simulation result
    │
    ├──[Approve]──→ approve_intent(id) via FRB
    │                  │ AgentServer.approve_intent(id) → status=Approved
    │                  │ Dart signs: sign_serialized_transaction(...)
    │                  │ submit to Solana RPC
    │                  │ update_intent_status(id, Confirmed, sig, None)
    │
    └──[Reject]───→ reject_intent(id) via FRB
                       │ status=Rejected
```

```
Agent polling: GET /intent/{id}/status
    ← {"id":"uuid","status":"confirmed","signature":"abc123..."}
```

### Auth Gate Flow

```
App Launch / Idle Timeout
    │
    ▼
AuthProvider checks: is_session_valid()  [sync FRB call]
    │
    ├──[valid]──→ continue to app
    │
    └──[invalid]──→ LockScreen
                      │
                      ├──[password]──→ verify_app_password(pw)  [FRB]
                      │                  scrypt hash check in Rust
                      │                  session token set
                      │                  wallets unlocked
                      │
                      └──[biometric]──→ local_auth.authenticate()  [Flutter plugin]
                                         on success: unlock_with_biometric()  [FRB]
                                         re-uses stored password hash → session token
```

### Vault Unlock Flow

```
User enters password in Flutter
    │ (password in Dart memory: String, short-lived)
    ▼
verify_app_password(password)  [FRB sync or async]
    │ Rust: scrypt(password, stored_salt) == stored_hash ?
    │ yes: SESSION.set(SessionToken { expires_at: now + timeout })
    │      WalletManager: decrypt vault from Keychain into memory
    │ no: return Err("Invalid password")
    ▼
Dart: password String goes out of scope (GC'd)
    │
Rust: seed bytes held in WalletManager session (zeroize on lock)
```

### ESP32 BIP39 Keypair Generation Flow

```
Flutter "Generate on Hardware" button
    │
    ▼
generate_hardware_bip39_keypair(port_path)  [FRB]
    │ Esp32Bridge::connect(port)
    │ send: {"cmd":"generate_bip39"}
    │
    ▼
ESP32-C3 firmware
    │ esp_random() → 16 bytes entropy → 12-word mnemonic
    │   OR 32 bytes entropy → 24-word mnemonic
    │ PBKDF2-HMAC-SHA512(mnemonic, "mnemonic", 2048) → 64-byte seed
    │ SLIP-0010 Ed25519 derive m/44'/501'/0'/0' → keypair
    │ NVS.put("seed", seed_bytes, 64)  — store seed, not private key
    │ response: {"status":"ok","pubkey":"<hex>","address":"<base58>"}
    │
    ▼
Rust bridge: register_hardware_wallet(name, address)
    │
    ▼
Flutter: navigate to mnemonic backup flow
    │ get_hardware_mnemonic(port_path)  → {"cmd":"get_mnemonic"}
    │ Display 12/24 words for user to write down
    │ Word quiz verification
    │ Mark backup complete
```

### Key Data Flows Summary

1. **Agent intent arrival:** HTTP POST → mpsc channel → StreamSink → Dart stream → UI overlay
2. **Intent approval:** Dart FFI call → Rust state mutation → Dart calls sign FFI → Dart submits RPC → Dart calls update_status FFI
3. **App password unlock:** Dart string → FRB → scrypt in Rust → session token in Rust static → wallet seed in memory
4. **Biometric unlock:** Flutter local_auth → on success → FRB unlock_with_biometric → existing session reused
5. **Hardware signing:** Dart FFI → Rust Esp32Bridge → serial JSON → ESP32 button confirm → signature bytes → back to Dart

## Integration Points

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Flutter ↔ Rust (bridge) | flutter_rust_bridge v2 FFI | sync (frb sync) + async + StreamSink |
| deadbolt_bridge ↔ deadbolt_core | Direct Rust function calls (same process) | No overhead |
| AgentServer ↔ bridge API | Arc<Mutex<AgentServer>> in static OnceLock | Bridge functions access via global ref |
| axum server ↔ Dart | mpsc channel → StreamSink bridge task | Intent events only |
| Rust ↔ ESP32 | serialport crate, 115200 baud, JSON newlines, 64-byte chunks | Blocking serial calls use spawn_blocking or dedicated thread |
| AppConfig ↔ API tokens | api_tokens: Vec<String> in config.json | Server must reload on token add/revoke |

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| AI Agent (curl/HTTP) | REST to localhost:9876 | Bearer token, JSON body, polls for status |
| Solana RPC (Helius) | Dart http client | Transaction simulation + submission |
| macOS Keychain | security-framework Rust crate | Vault bytes stored per wallet address |
| ESP32-C3 | serialport crate over USB CDC | /dev/cu.* on macOS, chunked writes |
| local_auth (biometric) | Flutter plugin, Dart only | macOS Touch ID — delegates to LAContext |

## Anti-Patterns

### Anti-Pattern 1: Calling AgentServer from a Sync FRB Function

**What people do:** Expose `start_agent_server` as a regular `pub fn` (not async), then call `Runtime::new().block_on(AgentServer::start(...))` inside it.

**Why it's wrong:** FRB v2 runs sync functions on a thread pool. Creating a new tokio runtime inside an existing tokio context (FRB's) panics with "Cannot start a runtime from within a runtime."

**Do this instead:** Mark `start_agent_server` as `pub async fn`. FRB will run it inside its own multi-threaded tokio runtime, where `tokio::spawn` and `TcpListener::bind` work correctly.

### Anti-Pattern 2: Polling Intent Status from Dart

**What people do:** Dart calls `get_pending_intents()` on a timer every 500ms to check for new intents from agents.

**Why it's wrong:** Adds 0–500ms latency to every agent request, burns CPU, and requires the FRB thread pool to wake up constantly.

**Do this instead:** Use the `StreamSink<IntentEventDto>` pattern. The `mpsc::UnboundedReceiver` in the bridge task wakes only when an intent arrives.

### Anti-Pattern 3: Storing Password in Dart State

**What people do:** Save the user's app password in a Riverpod provider or Flutter `SharedPreferences` so the app can re-unlock on idle timeout without asking again.

**Why it's wrong:** The password ends up in Dart's GC heap for the entire session, visible to heap dumps and memory forensics.

**Do this instead:** After initial verification, Rust holds a session token with an expiry timestamp. Dart stores nothing. When the session expires, ask for the password again (or biometric). The Rust session token lives in a `Mutex<Option<SessionToken>>` and gets zeroized on lock.

### Anti-Pattern 4: Storing Private Keys or Seeds on ESP32 in Plaintext NVS

**What people do:** Store the 32-byte private key directly in ESP32 NVS `Preferences` with no protection.

**Why it's wrong:** NVS on ESP32-C3 is unencrypted flash by default. The current firmware does this — it's the primary reason for the rewrite.

**Do this instead:** Store the 64-byte BIP39 seed in NVS instead of the raw private key. The seed is not directly usable without SLIP-0010 derivation. For stronger protection, enable ESP-IDF NVS encryption using the device's eFuse-derived key (available on ESP32-C3 with IDF v5+). The private key is derived at signing time and never stored.

### Anti-Pattern 5: Signing Intent Approval Without Guardrails Re-check

**What people do:** When the user approves an intent in the UI, call the signer directly without re-running guardrails.

**Why it's wrong:** A race condition allows an agent to fill the queue with many intents just below the per-tx limit. When the user approves them one by one, the daily limit can be exceeded.

**Do this instead:** Re-run `GuardrailsEngine.check()` at approval time (after simulation, with the real USD value). The initial check at POST time is an early rejection gate; the approval-time check is the authoritative enforcement.

## Build Order Implications

The component dependency graph dictates this build sequence:

1. **Auth layer (Rust + Dart)** must come first. Every subsequent feature requires `check_session_valid()` and `verify_app_password()`. Adding auth after agent signing creates a security gap.

2. **Agent API bridge exposure** (new `api/agent.rs` in deadbolt_bridge) comes second. The `AgentServer` code exists in `deadbolt_core` but is not yet wired to FRB. This is the highest-priority missing piece.

3. **Guardrails UI + settings** can be built in parallel with the agent bridge, since `GuardrailsEngine` and `GuardrailsConfig` already exist in Rust.

4. **ESP32 firmware rewrite** is independent of the agent API and auth work. It depends only on the existing serial protocol types in `hardware/esp32_bridge.rs`. Can proceed in parallel with the above.

5. **Agent signing prompt overlay** depends on: (a) the StreamSink event stream working, (b) auth gate being in place to block unsigned intents from bypassing user approval.

## Sources

- Direct codebase inspection: `rust/deadbolt_core/src/agent/`, `rust/deadbolt_bridge/src/api/`, `firmware/unruggable_esp32/`
- flutter_rust_bridge v2 StreamSink documentation: https://cjycode.com/flutter_rust_bridge/guides/types/translatable/stream
- axum 0.8 announcement (tokio runtime requirements): https://tokio.rs/blog/2025-01-01-announcing-axum-0-8-0
- BIP39 specification (PBKDF2-HMAC-SHA512, 2048 iterations): https://bips.dev/39/
- ESP32-C3 memory architecture: https://developer.espressif.com/blog/2024/08/esp32-memory-map-101/
- local_auth Flutter plugin (macOS Touch ID): https://pub.dev/packages/local_auth

---
*Architecture research for: Deadbolt — agent API server, auth system, guardrails, ESP32 BIP39 firmware*
*Researched: 2026-03-16*
