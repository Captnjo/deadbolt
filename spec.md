# Deadbolt — Cross-Platform Solana Wallet Specification

## Context

Deadbolt is a cross-platform native wallet for Solana with ESP32 hardware wallet support and an embedded agent API. Built with **Flutter** (UI) and **Rust** (crypto, signing, transaction building), it runs on macOS, Windows, Linux, iOS, and Android.

Key principle: **private keys never leave Rust**. Only public keys, serialized transactions, signatures, and vault encryption keys cross the FFI bridge. Seeds and private signing keys are generated, stored, and used exclusively within the Rust process.

### Why a Standalone App

Deadbolt is a native app — not a website, browser extension, or wrapper around existing wallets. This decision is driven by three requirements:

1. **Agent API** — AI agents POST transaction intents to `localhost:9876`. A native app can bind a port and run an HTTP server. Browser extensions and websites cannot.
2. **ESP32 hardware wallet** — Native USB serial access. No WebSerial limitations, no browser dependency.
3. **Zero infrastructure** — No backend servers, no relay services, no cloud dependencies. The user installs the app once and everything runs locally.

Using Phantom/Solflare SDKs was considered and rejected: those SDKs connect dApps to existing wallets. Deadbolt **is** the wallet — it holds keys, enforces guardrails, and produces signatures. Delegating signing to another wallet would break the agent API flow, bypass guardrails, and eliminate the hardware wallet path.

---

## Architecture

### Flutter UI (Dart)
All screens, state management (Riverpod), navigation (go_router), HTTP API clients (RPC, Jupiter, Helius, Jito, DFlow), app config/address book persistence, biometric auth prompts.

### Rust Core (`deadbolt_core` crate)
Ed25519 signing (`ed25519-dalek`), Base58 (`bs58`), BIP39 mnemonic (`bip39`), vault encryption (ChaCha20-Poly1305), key derivation (scrypt), transaction building & serialization (legacy + v0), program instructions (System, Token, ComputeBudget, JitoTip), PDA derivation, secure storage trait with platform backends, ESP32 serial bridge, agent API server (`axum`), guardrails engine.

### FFI Bridge (`deadbolt_bridge` crate via `flutter_rust_bridge`)
Thin layer exposing Rust functions to Dart. Wallet management returns public info only, never seeds. Transaction building + signing keeps key material in Rust.

### Signing Paths

Two signing backends, abstracted behind the `TransactionSigner` trait:

```
Agent / User action
    → Guardrails check (Rust)
    → User approval (Flutter UI)
    ├→ Software wallet: Rust decrypts vault → signs with ed25519-dalek → submits
    └→ ESP32 hardware: Rust builds tx → sends message bytes over USB serial → ESP32 signs → Rust attaches signature → submits
```

---

## Secure Key Storage

### Design Principles

All wallets follow the same fundamental pattern (verified against Phantom, MetaMask, Backpack, Solflare, and Rabby):

1. Seed phrase encrypted with a symmetric cipher into a vault blob stored on disk
2. Encryption key derived from user password via a memory-hard KDF
3. The derived key (or password) cached in platform secure storage, hardware-backed where available
4. Biometric unlock gates access to the secure storage entry
5. Private key decrypted into process memory only during signing, then zeroized

Android Keystore and Apple Secure Enclave **cannot perform Ed25519 signing** — only standard algorithms (RSA, ECDSA P-256). All mobile wallets must decrypt the private key into application memory to sign Solana transactions. The hardware-backed storage protects the vault encryption key at rest, not the signing key during use. The ESP32 path is the only way to keep the signing key off the host device entirely.

### Vault Architecture (Rust)

```
Seed phrase (32 bytes)
    → encrypted with ChaCha20-Poly1305
    → encryption key derived via scrypt(password, salt)
    → encrypted vault blob stored on disk: ~/.deadbolt/vault/<address>.vault
    → scrypt-derived key cached in platform secure storage for session
    → biometric/password unlock gates access to cached key
```

Vault file format (all fields concatenated):
```
[1 byte: version] [16 bytes: salt] [12 bytes: nonce] [48 bytes: ciphertext + tag]
```

Mnemonic phrases stored in a separate vault file per address: `~/.deadbolt/vault/<address>.mnemonic.vault` (same encryption scheme).

### Platform Backends

The `SecureStorage` trait abstracts platform-specific secure storage for caching the vault encryption key (not the seed itself):

| Platform | API | Crate / Package | Hardware-Backed | Notes |
|----------|-----|------------------|-----------------|-------|
| **macOS** | Keychain Services | `security-framework` | Yes (Secure Enclave on T2/Apple Silicon) | Service: `com.deadbolt.wallet`. Compatible with existing Swift app data. |
| **iOS** | Keychain Services | `security-framework` | Yes (Secure Enclave) | Same API as macOS. Access control: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Biometric via `kSecAccessControlBiometryCurrentSet`. |
| **Windows** | DPAPI + Credential Manager | `windows` crate (`CryptProtectData`) | Yes (TPM when available) | Data encrypted to current user profile. Survives password resets if user has recovery key. |
| **Linux** | Secret Service API (GNOME Keyring / KDE Wallet) | `secret-service` crate | No (software-only, encrypted at rest with login password) | Falls back to encrypted file if no keyring daemon available. |
| **Android** | Android Keystore | `flutter_secure_storage` (Dart) | Yes (TEE / StrongBox on supported devices) | See hybrid flow below. |

### Android Hybrid Flow

Android Keystore is a Java API inaccessible from Rust directly. Deadbolt uses a hybrid approach that keeps the seed in Rust while leveraging hardware-backed storage:

```
Setup (wallet creation):
1. Rust generates seed + derives keypair
2. Rust generates random 32-byte vault encryption key
3. Rust encrypts seed with ChaCha20-Poly1305 using vault key → writes vault file
4. Vault key passed to Dart via FFI
5. Dart stores vault key in Android Keystore via flutter_secure_storage
6. Vault key zeroized in Rust memory

Unlock (wallet access):
1. User authenticates via biometric (BiometricPrompt) or PIN
2. Dart reads vault key from Android Keystore
3. Vault key passed to Rust via FFI
4. Rust decrypts vault → loads seed into memory for signing session
5. On lock: Rust zeroizes seed from memory
```

The seed never crosses FFI. Only the 32-byte vault encryption key crosses the bridge, and it is protected by hardware-backed storage on the device.

### Session Lifecycle

```
App launch → locked (no keys in memory)
    → biometric/password prompt
    → platform secure storage releases vault key
    → Rust decrypts vault, loads seed into memory
    → app is unlocked (signing available)
    → user locks / app backgrounds / timeout
    → Rust zeroizes seed from memory
    → back to locked state
```

Auto-lock triggers: app backgrounded (mobile), screen lock (desktop), configurable idle timeout (default: 5 minutes).

---

## Project Structure

```
deadbolt/
  rust/
    Cargo.toml                    # workspace
    deadbolt_core/src/
      crypto/                     # base58, pubkey, signer, mnemonic, vault
      solana/                     # compact_u16, instruction, message, versioned_message,
                                  # transaction, pda, address_lookup_table
        programs/                 # system_program, token_program, compute_budget, jito_tip
      storage/                    # SecureStorage trait + platform backends
                                  #   keychain (macOS/iOS), dpapi (Windows),
                                  #   secret_service (Linux), memory (test)
      hardware/                   # ESP32 detector + serial bridge (Phase 5)
      agent/                      # axum server + guardrails (Phase 6)
      models/                     # error, wallet types
    deadbolt_bridge/src/
      lib.rs                      # flutter_rust_bridge annotated functions

  lib/                            # Flutter/Dart
    main.dart
    app.dart                      # MaterialApp, theme, routing
    theme/brand_theme.dart
    routing/app_router.dart       # go_router (sidebar desktop, tabs mobile)
    providers/                    # Riverpod notifiers
    models/                       # Dart data classes
    services/                     # HTTP clients (RPC, Jupiter, Helius, etc.)
    data/                         # app_config, address_book, token_registry
    features/
      dashboard/                  # dashboard_screen + widgets
      send/                       # send flow (token selector, recipient, amount, review)
      swap/                       # swap flow (input/output, quotes, review)
      wallet/                     # wallet_list, create_wallet, import_wallet
      settings/                   # settings, auth, guardrails, hardware
      agent/                      # agent_api_screen, signing_prompt
      history/                    # history_screen, transaction_detail
      receive/                    # receive_screen (QR)
      address_book/
    shared/                       # inline_review_section, confirmation_view
  macos/ ios/ windows/ linux/ android/
```

---

## FFI Bridge Functions

```
// Wallet management — returns public info only, never seeds
create_wallet(name) -> WalletInfo
import_wallet_from_mnemonic(words, name) -> WalletInfo
list_wallets() -> Vec<WalletInfo>
remove_wallet(address)
get_mnemonic(address) -> Vec<String>  // requires auth gate, returns from decrypted vault

// Vault management
unlock_vault(address, vault_key: Vec<u8>) -> bool
lock_vault(address)  // zeroizes seed from memory
is_unlocked(address) -> bool

// Transaction building + signing (key material stays in Rust)
build_and_sign_send_sol(params) -> SignedTransaction
build_and_sign_send_token(params) -> SignedTransaction
build_and_sign_swap(params) -> SignedTransaction

// Hardware wallet
scan_for_esp32() -> Vec<String>
esp32_connect(port_path) -> String  // returns pubkey
esp32_disconnect()

// Agent API server
start_agent_server(port, config)
stop_agent_server()
approve_agent_request(request_id)
reject_agent_request(request_id)

// Streams (Rust -> Dart via StreamSink)
subscribe_agent_requests(sink)
subscribe_esp32_status(sink)
```

---

## Key Dependencies

**Rust:** `ed25519-dalek`, `bs58`, `bip39`, `sha2`, `hmac`, `chacha20poly1305`, `scrypt`, `rand`, `getrandom`, `base64`, `serde`, `serde_json`, `thiserror`, `zeroize`

Platform-specific:
- macOS/iOS: `security-framework`
- Linux: `secret-service`
- Windows: `windows` (DPAPI)

Future phases: `serialport` (ESP32), `axum` + `tokio` + `tower` (agent API)

**Flutter:** `flutter_riverpod`, `go_router`, `flutter_rust_bridge`, `dio`, `local_auth`, `flutter_secure_storage`, `qr_flutter`, `path_provider`, `window_manager`

---

## Screens

### Dashboard (Home)
- Wallet address (with [HW WALLET] indicator when ESP32 connected)
- SOL balance + USD value
- Token list: name, balance, per-token price, USD value
- Total portfolio USD value
- Quick action toolbar

### Send SOL / Token / NFT
- Step 1: Recipient picker (manual, wallet list, address book)
- Step 2: Amount entry (with max, USD conversion)
- Step 3: Inline review (balance changes, fee breakdown, simulation status, warnings)
- Step 4: Confirmation tracker (Submitted -> Confirmed -> Finalized)

### Swap (Jupiter / DFlow)
- Input token + amount, output token
- Debounced live quotes with aggregator toggle
- Inline review + confirmation tracker

### Receive
- Wallet address + QR code + copy button

### Transaction History
- Paginated from Helius Enhanced Transactions API
- Human-readable descriptions, filter by type

### Wallet Management
- List, create (with mnemonic), import, rename, delete

### Settings
- Auth (system/password/biometric)
- Hardware wallet (detect, connect, status)
- Agent API (server start/stop, API key management)
- Guardrails (daily limits, cooldowns, whitelists)
- Network switching (mainnet/devnet)

---

## External APIs

| Service | Endpoint | Purpose |
|---------|----------|---------|
| Helius RPC | `https://mainnet.helius-rpc.com/?api-key={KEY}` | Standard Solana JSON-RPC |
| Helius Enhanced | `https://api.helius.xyz/v0/transactions/` | Transaction parsing |
| Helius DAS | via RPC `getAssetsByOwner` | Token + NFT metadata |
| Jupiter Quote | `https://quote-api.jup.ag/v6/quote` | Swap quotes |
| Jupiter Swap | `https://quote-api.jup.ag/v6/swap-instructions` | Swap instruction generation |
| DFlow | `https://api.dflow.net/...` | Pre-built swap transactions |
| Jito Transactions | `https://mainnet.block-engine.jito.wtf/api/v1/transactions` | MEV-protected submission |
| Jito Bundles | `https://mainnet.block-engine.jito.wtf/api/v1/bundles` | Bundle submission |

---

## Hardware Wallet (ESP32)

JSON serial protocol (unchanged from CLI/Swift app):

| Command | Request | Response |
|---------|---------|----------|
| Ping | `{"cmd":"ping"}` | `{"status":"ok","msg":"pong"}` |
| Get pubkey | `{"cmd":"pubkey"}` | `{"status":"ok","pubkey":"<hex>","address":"<base58>"}` |
| Sign | `{"cmd":"sign","payload":"<hex msg>"}` | `{"status":"pending",...}` then `{"status":"signed","signature":"<hex>"}` |

Sign flow: LED pulses -> user presses BOOT within 30s -> signature returned.

`TransactionSigner` trait in Rust abstracts software vs hardware signing. The ESP32 is the only path where the private key never touches the host device at all — it lives exclusively on the microcontroller.

---

## Agent API Protocol

Embedded HTTP server on `localhost:9876` allowing AI agents to propose transactions:

### Endpoints
| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` | Health check |
| POST | `/intent` | Submit a transaction intent |
| GET | `/intent/{id}/status` | Check intent status |
| GET | `/wallet` | Get active wallet info |
| GET | `/balance` | Get SOL balance |
| GET | `/tokens` | Get token balances |
| GET | `/price/{mint}` | Get token price |
| GET | `/history` | Get transaction history |

### Auth
Bearer token: `Authorization: Bearer db_<hex>`. Tokens managed in config.json `apiTokens` array.

### Intent Flow
1. Agent POSTs intent (send_sol, send_token, swap)
2. Server queues request, streams to Flutter UI
3. User sees signing prompt overlay with full preview
4. User approves/rejects
5. If approved: Rust builds + signs + submits transaction
6. Agent polls status endpoint for confirmation

### Guardrails
- Max SOL per transaction
- Max USD per transaction
- Max daily transaction count
- Max daily USD total
- Token whitelist
- Program whitelist
- Cooldown between transactions

Guardrails are enforced at the Rust layer before signing. Because Deadbolt owns the signing key, guardrails cannot be bypassed — unlike a wrapper around an external wallet where the user could open the wallet directly.

---

## Data Compatibility

- `~/.deadbolt/config.json` format preserved (same JSON structure)
- `~/.deadbolt/vault/` directory for encrypted vault files (new)
- macOS Keychain vault keys accessible via Rust `security-framework` (service: `com.deadbolt.wallet`)
- Mnemonic vault keys (service: `com.deadbolt.wallet.mnemonic`)
- Address book JSON format preserved

### Migration from Swift App

On macOS, existing seeds stored directly in Keychain by the Swift app will be detected and migrated to the new vault format on first launch. The migration reads the raw seed from Keychain, encrypts it into a vault file, stores the vault key back in Keychain, and deletes the raw seed entry.

---

## Implementation Phases

| Phase | Scope | Status |
|-------|-------|--------|
| 1 | Rust Core: crypto, transaction primitives, programs, PDA, storage trait, tests | **Complete** (57 tests) |
| 2 | Vault + Storage Backends: ChaCha20-Poly1305 vault, scrypt KDF, platform backends, migration | Pending |
| 3 | Flutter Shell: theme, navigation, layout, Riverpod, wallet screens | **Complete** |
| 4 | Dashboard + Network Clients: HTTP clients, balance/token fetch, dashboard UI | **Complete** |
| 5 | Transaction Flows: send, swap, inline review, confirmation | **Complete** |
| 6 | Hardware Wallet: ESP32 detection + serial bridge in Rust, desktop UI | Partial (detection done, signing pending) |
| 7 | Agent API: axum server, auth, request queue, guardrails, signing prompt | Pending |
| 8 | Polish: auth service, history, receive, address book, migration, platform testing | **Mostly Complete** (auth pending) |

---

## Testing Strategy

- **Rust unit tests**: Ed25519 sign/verify, Base58 round-trips, CompactU16 encoding, transaction serialization byte comparison against web3.js 1.91.4, BIP39/SLIP-0010 derivation with known vectors, PDA computation, Jito tip bounds, vault encrypt/decrypt round-trips, scrypt key derivation
- **Compatibility tests**: 24 tests ported from Swift DeadboltCore ensuring byte-for-byte identical output
- **Storage tests**: Platform-specific secure storage read/write (Keychain, DPAPI, Secret Service), vault migration from legacy format
- **Flutter widget tests**: UI component behavior
- **Integration tests**: Devnet transactions for each type, hardware wallet mock, agent API end-to-end (intent → approve → sign → confirm)

---

## Security Summary

| Threat | Mitigation |
|--------|-----------|
| Key extraction from disk | Seeds encrypted at rest with ChaCha20-Poly1305; vault key in hardware-backed secure storage |
| Key extraction from memory | Seeds zeroized (`zeroize` crate) on lock/background; minimal time in memory |
| Malicious agent transaction | Guardrails enforced at signing layer in Rust; user approval prompt with full preview |
| Bypassing guardrails | Keys owned by Deadbolt, not delegated to external wallet; no alternative signing path |
| Device theft (locked) | Biometric/password required to unlock vault; auto-lock on background/idle |
| Device theft (unlocked) | Agent API requires bearer token; manual transactions require app interaction |
| Supply chain (dependencies) | Minimal dependency tree; crypto via audited crates (`ed25519-dalek`, `chacha20poly1305`) |
| Man-in-the-middle (RPC) | All external API calls over HTTPS; agent API on localhost only |
