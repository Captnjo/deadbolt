# Deadbolt — Architecture & Flow

> The lock between your agent and your keys.

---

## What Is Deadbolt?

A cross-platform wallet for Solana that doubles as a **signing gateway for AI agents**. Built with Flutter (UI) and Rust (crypto, signing, transaction building). Agents propose DeFi transactions via REST API, the user previews and approves them, and the app signs with either a software wallet (Rust vault) or a $5 ESP32 hardware signer. The agent never touches the keys.

---

## System Overview

```
┌─────────────────────────────────────────────────────────┐
│  AI Agents (OpenClaw, custom bots, cloud-hosted)        │
│  POST structured JSON intents via REST                  │
└────────────┬───────────────────────────┬────────────────┘
             │ localhost:9876            │ remote
             ▼                          ▼
┌────────────────────────┐   ┌──────────────────────────┐
│  Embedded HTTP Server  │   │  Bridge Service (Python)  │
│  axum, in-app (Rust)   │   │  FastAPI, port 9877       │
│  Port 9876             │   │  Forwards to localhost    │
└───────────┬────────────┘   └────────────┬─────────────┘
            │                             │
            └──────────┬──────────────────┘
                       ▼
┌─────────────────────────────────────────────────────────┐
│              Flutter UI + Rust Core                      │
│                                                         │
│  ┌──────────┐  ┌────────────┐  ┌──────────────────────┐│
│  │ Guardrails│→│  Request    │→│  Signing Prompt (UI)  ││
│  │ Engine    │  │  Queue     │  │  Preview + Approve    ││
│  └──────────┘  └────────────┘  └──────────┬───────────┘│
│                                            │            │
│                                 ┌──────────┴─────────┐  │
│                                 │                    │  │
│                          Software            ESP32   │  │
│                          (Rust vault)      (Serial)  │  │
└─────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
rust/
  deadbolt_core/src/
    crypto/              # base58, pubkey, signer, mnemonic, vault
    solana/              # transaction builder, message serialization, PDAs
      programs/          # system, token, compute_budget, jito_tip
    storage/             # SecureStorage trait + platform backends
    hardware/            # ESP32 detector + serial bridge
    agent/               # axum server + guardrails
    models/              # error types, wallet types
  deadbolt_bridge/       # flutter_rust_bridge FFI layer

lib/                     # Flutter/Dart
  main.dart
  app.dart               # MaterialApp, theme, routing, title bar
  theme/brand_theme.dart # Brand colors + ThemeData
  routing/app_router.dart # GoRouter (sidebar desktop, tabs mobile)
  providers/             # Riverpod notifiers (wallet, balance, network, send, swap, etc.)
  models/                # Dart data classes (token, send, stake, transaction_history)
  services/              # HTTP clients (RPC, Helius, Jupiter, DFlow, Jito, price)
  features/
    dashboard/           # Portfolio view (SOL + token balances, NFTs, USD values)
    send/                # Send SOL/token flow
    swap/                # Jupiter/DFlow swap flow
    receive/             # QR code + address copy
    nft/                 # Send NFT flow
    history/             # Transaction history (Helius Enhanced API)
    address_book/        # Contact management (CRUD + search)
    wallet/              # Wallet management (create, import, hardware)
    settings/            # Network, API keys, preferences
    onboarding/          # First-run wizard
  shared/                # App shell, title bar, wallet drawer, formatters, widgets

DeadboltWallet/          # Legacy Swift macOS app (superseded by Flutter)
firmware/                # ESP32 Arduino firmware for hardware signing
bridge/                  # Python FastAPI service for remote agent access
calypso/                 # Legacy Node.js transaction modules
content/                 # Brand guidelines
```

---

## Core Protocols

### TransactionSigner

The central abstraction. Both signing modes implement the same trait in Rust:

```rust
pub trait TransactionSigner: Send + Sync {
    fn public_key(&self) -> &SolanaPublicKey;
    fn sign(&self, message: &[u8]) -> Result<[u8; 64]>;
}
```

| Implementation | Where keys live | How user approves |
|---|---|---|
| `SoftwareSigner` | Encrypted vault (ChaCha20-Poly1305) | Click "Approve" in app |
| `ESP32SerialBridge` | ESP32 flash memory | Press BOOT button on device |

The agent never sees either. It only gets back a `request_id` to poll.

### WalletSource

```rust
enum WalletSource {
    Software,    // Hot wallet — seed in encrypted vault
    Hardware,    // Cold wallet — ESP32 via USB serial
}
```

---

## Data Flows

### 1. Agent Intent Flow (the main event)

```
Agent                    IntentServer              GuardrailsEngine
  │                          │                           │
  │  POST /intent            │                           │
  │  {type, params, meta}    │                           │
  │─────────────────────────▶│                           │
  │                          │  evaluate(intent, price)  │
  │                          │──────────────────────────▶│
  │                          │                           │
  │                          │◀─ .allowed / .rejected ───│
  │                          │                           │
  │  403 Guardrail rejected  │  (if rejected)            │
  │◀─────────────────────────│                           │
  │                          │                           │
  │  200 {request_id,        │  (if allowed)             │
  │       status: pending,   │                           │
  │       preview}           │                           │
  │◀─────────────────────────│                           │
  │                          │                           │
  │                          │  ┌─────────────────────┐  │
  │                          │  │ RequestQueue adds    │  │
  │                          │  │ AgentRequest, emits  │  │
  │                          │  │ via AsyncStream      │  │
  │                          │  └────────┬────────────┘  │
  │                          │           │               │
  │                          │           ▼               │
  │                    ┌─────────────────────────────┐   │
  │                    │  AgentSigningPromptView      │   │
  │                    │                             │   │
  │                    │  Agent: dca-bot             │   │
  │                    │  Action: Swap 1 SOL → USDC  │   │
  │                    │  Fees: 0.001045 SOL         │   │
  │                    │  Simulation: ✓ Success      │   │
  │                    │                             │   │
  │                    │  [Reject]    [Approve & Sign]│   │
  │                    └─────────────────────────────┘   │
  │                          │                           │
  │  (user clicks Approve)   │                           │
  │                          │                           │
  │                    ┌─────────────────────┐           │
  │                    │ createSigner()      │           │
  │                    │  → SoftwareSigner   │           │
  │                    │  or ESP32SerialBridge│           │
  │                    └────────┬────────────┘           │
  │                             │                        │
  │                    ┌────────▼────────────┐           │
  │                    │ IntentRouter        │           │
  │                    │  .processIntent()   │           │
  │                    │  → build tx         │           │
  │                    │  → sign             │           │
  │                    │  → simulate         │           │
  │                    └────────┬────────────┘           │
  │                             │                        │
  │                    ┌────────▼────────────┐           │
  │                    │ TransactionBuilder  │           │
  │                    │  .submitViaJito()   │           │
  │                    │  → Jito bundle API  │           │
  │                    └────────┬────────────┘           │
  │                             │                        │
  │                    RequestQueue.setConfirmed()        │
  │                             │                        │
  │  GET /status/{id}           │                        │
  │─────────────────────────────▶                        │
  │  200 {status: confirmed,   │                        │
  │       signature: "5xYz.."} │                        │
  │◀─────────────────────────── │                        │
```

### 2. Hardware Wallet Signing

```
App                      ESP32SerialBridge            ESP32 Device
 │                            │                          │
 │  loadHardwareSigner()      │                          │
 │───────────────────────────▶│                          │
 │                            │  {"cmd":"ping"}          │
 │                            │─────────────────────────▶│
 │                            │  {"status":"ok"}         │
 │                            │◀─────────────────────────│
 │                            │                          │
 │  sign(message)             │                          │
 │───────────────────────────▶│                          │
 │                            │  {"cmd":"sign",          │
 │                            │   "payload":"<hex>"}     │
 │                            │──(chunked 64B + 5ms)────▶│
 │                            │                          │ LED pulses
 │                            │  {"status":"pending"}    │
 │                            │◀─────────────────────────│
 │                            │                          │
 │  UI: "Press BOOT button"   │         (user presses)   │
 │   (shown via callback)     │                          │
 │                            │  {"status":"signed",     │
 │                            │   "signature":"<hex>"}   │ (30s timeout)
 │                            │◀─────────────────────────│
 │  ◀── 64-byte signature ───│                          │
```

### 3. Manual Send Flow (no agent)

```
User → SendScreen
  Step 1: Pick recipient (address book dropdown or paste address)
  Step 2: Select asset (SOL or SPL token) + enter amount
  Step 3: Preview (simulate tx, show fees + balance changes)
  Step 4: Approve → loadSigner → build tx → submit via Jito (mainnet) or RPC
  Step 5: Confirmation polling until finalized
```

Swap flow follows the same pattern with Jupiter/DFlow builders.

### 4. Swap Aggregator Toggle

Swaps support two DEX aggregators, selectable in Settings or inline during the swap flow:

| Aggregator | Flow | Submission |
|------------|------|------------|
| **DFlow** (default) | `GET /order` → pre-built base64 tx → deserialize, sign, submit | Standard RPC |
| **Jupiter** | `GET /quote` → `POST /swap-instructions` → build v0 tx, sign | Jito bundle (mainnet) |

The preference persists in `~/.deadbolt/config.json` as `preferredSwapAggregator`.

### 5. Network-Aware Submission

| Network | SOL/Token Send | Swap (Jupiter) | Swap (DFlow) |
|---------|---------------|-----------------|--------------|
| Mainnet | Jito bundle + tip | Jito bundle + tip | Standard RPC |
| Devnet | Standard RPC, no tip | Standard RPC, no tip | Standard RPC |

---

## Intent API

**Base URL:** `http://localhost:9876/api/v1`
**Auth:** `Authorization: Bearer db_<hex>`

### Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/health` | No | `{"status":"ok","service":"deadbolt"}` |
| `POST` | `/intent` | Yes | Submit an intent for approval |
| `GET` | `/status/:id` | Yes | Poll intent status |
| `GET` | `/wallet` | Yes | Active wallet address + source |
| `GET` | `/balance` | Yes | SOL balance + portfolio USD |
| `GET` | `/tokens` | Yes | Token holdings with prices |
| `GET` | `/price?mint=` | Yes | Price for a specific token |
| `GET` | `/history?limit=` | Yes | Recent transaction history |
| `GET` | `/subscribe?since=&timeout=` | Yes | Long-poll for status updates |

### Intent Types

| Type | Params | Description |
|------|--------|-------------|
| `send_sol` | `recipient`, `amount` (lamports) | Transfer SOL |
| `send_token` | `recipient`, `mint`, `amount`, `decimals?` | Transfer SPL token |
| `swap` | `input_mint`, `output_mint`, `amount`, `slippage_bps?` | Jupiter/DFlow swap |
| `sign_message` | `message` | Sign arbitrary message |
| `create_wallet` | `source?`, `name?` | Generate new keypair |
| `batch` | `intents[]` | Multiple intents atomically |

### Status Lifecycle

```
pending_approval → building → signing → submitted → confirmed
                                                   → failed
               → rejected (user or guardrails)
```

---

## Guardrails

Configurable safety rules evaluated *before* an intent reaches the signing prompt. Stored in `~/.deadbolt/config.json`.

| Rule | Default | Effect |
|------|---------|--------|
| Max SOL per tx | 10 SOL | Auto-reject (HTTP 403) |
| Max USD per tx | $1,000 | Auto-reject |
| Daily tx count | 50 | Auto-reject after limit |
| Daily USD spent | $5,000 | Auto-reject |
| Token whitelist | (empty = allow all) | Reject swaps with unknown tokens |
| Program whitelist | (empty = allow all) | Reject txs touching unknown programs |
| Cooldown per agent | 5 seconds | Rate-limit repeat submissions |

---

## External Services

| Service | Used For | Client |
|---------|----------|--------|
| Helius RPC | Solana JSON-RPC, enhanced tx history | `SolanaRPCClient`, `HeliusClient` |
| Jupiter v6 | Swap quotes + instructions | `JupiterClient` |
| DFlow | Swap quotes (returns pre-built tx) | `DFlowClient` |
| Jito Block Engine | MEV-protected bundle submission (mainnet only) | `JitoClient` |
| CoinGecko | SOL/USD price | `PriceService` |

---

## Config & Storage

| Path | Contents |
|------|----------|
| `~/.deadbolt/config.json` | Network, API keys (Helius/Jupiter/DFlow), swap aggregator preference, wallet names, guardrails |
| `~/.config/solana/deadbolt/` | Keypair files (JSON), token definitions |
| macOS Keychain (`com.deadbolt.wallet`) | Hot wallet seeds |
| ESP32 flash (Preferences) | Hardware wallet Ed25519 private key |

All settings changed in the Settings UI persist to `~/.deadbolt/config.json` and survive app restarts/rebuilds.

---

## Bridge (Remote Agents)

For agents that can't reach `localhost:9876` (cloud-hosted, different machine):

```
Cloud Agent → Bridge (FastAPI, port 9877) → localhost:9876 (Deadbolt app)
```

The bridge is a transparent HTTP proxy. Same auth token, same endpoints. Keys never leave the user's machine. The bridge forwards requests and polls status on behalf of remote agents.

**Run:** `deadbolt-bridge` (pip install from `bridge/`)
**Config:** Same `~/.deadbolt/config.json` or env vars (`DEADBOLT_API_TOKEN`, `DEADBOLT_UPSTREAM_URL`)

---

## Build & Run

```bash
# Flutter app (macOS)
flutter pub get
flutter run -d macos

# Release build
flutter build macos

# Rust core tests
cd rust/deadbolt_core && cargo test

# Bridge (remote agents)
cd bridge && pip install -e . && deadbolt-bridge

# ESP32 firmware
# Open firmware/unruggable_esp32/unruggable_esp32.ino in Arduino IDE
# Board: ESP32-C3, upload via USB
```
