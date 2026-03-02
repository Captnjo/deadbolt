# Deadbolt — Architecture & Flow

> The lock between your agent and your keys.

---

## What Is Deadbolt?

A native macOS wallet for Solana that doubles as a **signing gateway for AI agents**. Agents propose DeFi transactions via REST API, the user previews and approves them, and the app signs with either a hot wallet (CryptoKit) or a $5 ESP32 hardware signer. The agent never touches the keys.

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
│  Hummingbird, in-app   │   │  FastAPI, port 9877       │
│  Port 9876             │   │  Forwards to localhost    │
└───────────┬────────────┘   └────────────┬─────────────┘
            │                             │
            └──────────┬──────────────────┘
                       ▼
┌─────────────────────────────────────────────────────────┐
│                  Deadbolt Swift App                      │
│                                                         │
│  ┌──────────┐  ┌────────────┐  ┌──────────────────────┐│
│  │ Guardrails│→│  Request    │→│  Signing Prompt (UI)  ││
│  │ Engine    │  │  Queue     │  │  Preview + Approve    ││
│  └──────────┘  └────────────┘  └──────────┬───────────┘│
│                                            │            │
│                                 ┌──────────┴─────────┐  │
│                                 │                    │  │
│                          Hot Wallet            ESP32  │  │
│                          (CryptoKit)        (Serial)  │  │
└─────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
DeadboltWallet/
├── App/
│   ├── DeadboltApp.swift              # @main entry, navigation, overlay modals
│   ├── Server/
│   │   ├── IntentServer.swift           # Hummingbird HTTP server (actor)
│   │   ├── IntentRouter.swift           # Maps intents → TransactionBuilder calls
│   │   ├── IntentTypes.swift            # Request/response JSON models
│   │   ├── RequestQueue.swift           # FIFO queue with AsyncStream subscription
│   │   ├── AuthMiddleware.swift         # Bearer token validation
│   │   └── WalletStateProvider.swift    # Adapts WalletService for server actor
│   ├── Services/
│   │   ├── AgentService.swift           # Server lifecycle, token management
│   │   ├── WalletService.swift          # Wallet list, balances, network, settings
│   │   ├── AuthService.swift            # Biometric/password authentication
│   │   ├── PriceService.swift           # CoinGecko + Jupiter price feeds
│   │   ├── GuardrailsEngine.swift       # Safety rule evaluation (actor)
│   │   ├── MigrationService.swift       # One-time CLI data import
│   │   └── ConfirmationTracker.swift    # Poll tx confirmation status
│   ├── ViewModels/
│   │   ├── SendViewModel.swift          # SOL transfer flow
│   │   ├── SendTokenViewModel.swift     # SPL token transfer flow
│   │   ├── SwapViewModel.swift          # Jupiter swap flow
│   │   ├── StakeViewModel.swift         # Sanctum staking flow
│   │   ├── DashboardViewModel.swift     # Portfolio overview
│   │   └── HistoryViewModel.swift       # Transaction history
│   └── Views/
│       ├── Agent/
│       │   ├── AgentSigningPromptView.swift  # Modal for agent intent approval
│       │   └── AgentAPIView.swift            # API token management UI
│       ├── Dashboard/DashboardView.swift
│       ├── Send/SendFlowView.swift
│       ├── Swap/SwapFlowView.swift
│       ├── Stake/StakeFlowView.swift
│       ├── Settings/
│       │   ├── SettingsView.swift
│       │   └── GuardrailsSettingsView.swift
│       └── ...
│
├── Packages/
│   ├── DeadboltCore/                  # Platform-agnostic Swift library
│   │   └── Sources/DeadboltCore/
│   │       ├── Crypto/
│   │       │   ├── Ed25519Signer.swift      # TransactionSigner protocol + SoftwareSigner
│   │       │   ├── KeychainManager.swift    # macOS/iOS Keychain access
│   │       │   ├── KeypairReader.swift      # Discover keypair JSON files
│   │       │   ├── Base58.swift             # Base58 encode/decode
│   │       │   └── Mnemonic.swift           # BIP39 seed generation
│   │       ├── Solana/
│   │       │   ├── TransactionBuilder.swift # Build, sign, simulate, submit
│   │       │   ├── SolanaRPCClient.swift    # JSON-RPC via Helius
│   │       │   ├── Transaction.swift        # Legacy transaction
│   │       │   ├── VersionedTransaction.swift # v0 with address lookup tables
│   │       │   ├── SystemProgram.swift      # SOL transfers
│   │       │   ├── TokenProgram.swift       # SPL token ops
│   │       │   ├── ComputeBudgetProgram.swift
│   │       │   └── JitoTip.swift            # MEV tip instructions
│   │       ├── Network/
│   │       │   ├── JupiterClient.swift      # Swap quotes & instructions
│   │       │   ├── DFlowClient.swift        # DFlow swap orders (pre-built txs)
│   │       │   ├── SanctumClient.swift      # Liquid staking
│   │       │   ├── JitoClient.swift         # Bundle submission
│   │       │   ├── HeliusClient.swift       # Enhanced tx history
│   │       │   └── HTTPClient.swift         # Generic HTTP/JSON-RPC
│   │       ├── Models/
│   │       │   ├── Wallet.swift             # Wallet + WalletSource enum
│   │       │   ├── SolanaPublicKey.swift    # 32-byte key with Base58
│   │       │   ├── Token.swift              # TokenDefinition, TokenBalance
│   │       │   ├── DFlowTypes.swift         # DFlow API response models
│   │       │   └── SolanaError.swift
│   │       └── DataStore/
│   │           ├── AppConfig.swift          # Persisted settings (~/.deadbolt/config.json)
│   │           ├── GuardrailsConfig.swift   # Safety rule thresholds
│   │           ├── AddressBook.swift        # Saved addresses
│   │           └── DeadboltDirectories.swift  # Platform-specific paths
│   │
│   └── HardwareWallet/                  # macOS-only, ESP32 integration
│       └── Sources/HardwareWallet/
│           ├── ESP32SerialBridge.swift   # Actor, conforms to TransactionSigner
│           ├── ESP32Detector.swift       # USB serial port discovery
│           ├── ORSSerialPortAdapter.swift # ORSSerialPort wrapper
│           └── SerialPortProtocol.swift  # Abstraction for testing
│
├── bridge/                              # Python FastAPI proxy for remote agents
│   └── bridge/
│       ├── main.py                      # App creation + CLI entry point
│       ├── routes.py                    # Forward all endpoints to Swift app
│       ├── auth.py                      # Bearer token validation
│       ├── config.py                    # Load from ~/.deadbolt/config.json
│       ├── ws_client.py                 # StatusPoller (long-poll subscribe)
│       └── protocol.py                  # Protocol constants + docs
│
├── openclaw-plugin/                     # OpenClaw agent skill
│   ├── SKILL.md                         # Skill definition (YAML frontmatter)
│   ├── scripts/wallet.py               # CLI wrapper for all API operations
│   └── _meta.json                       # ClawHub registry metadata
│
├── firmware/                            # ESP32-C3 Arduino firmware
│   └── unruggable_esp32/
│       └── unruggable_esp32.ino       # Ed25519 keygen, signing, serial protocol
│
├── calypso/                             # Legacy Node.js reference code
│   ├── calypso.js                       # Jupiter swaps + Jito (reference)
│   ├── hermes.js                        # SOL transfers + Jito (reference)
│   ├── hermesSpl.js                     # SPL transfers + Jito (reference)
│   └── hw_signer.js                     # ESP32 serial protocol (Node.js version)
│
├── tests/
│   └── test_intent_api.sh              # 21-assertion integration test suite
│
├── content/
│   ├── launch-thread.md                 # X launch copy
│   └── logo-prompt.md                   # Logo generation prompt
│
└── spec.md                              # Full product specification
```

---

## Core Protocols

### TransactionSigner

The central abstraction. Both signing modes implement the same 2-method protocol:

```swift
public protocol TransactionSigner: Sendable {
    var publicKey: SolanaPublicKey { get }
    func sign(message: Data) async throws -> Data
}
```

| Implementation | Where keys live | How user approves |
|---|---|---|
| `SoftwareSigner` | macOS Keychain or keypair file | Click "Approve" in app |
| `ESP32SerialBridge` | ESP32 flash memory | Press BOOT button on device |

The agent never sees either. It only gets back a `request_id` to poll.

### WalletSource

```swift
enum WalletSource {
    case keychain          // Hot wallet — seed in macOS Keychain
    case keypairFile(path) // Hot wallet — JSON file on disk
    case hardware          // Cold wallet — ESP32 via USB serial
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
User → SendFlowView
  Step 1: Pick recipient (address book or paste)
  Step 2: Enter amount
  Step 3: Preview (simulate tx, show fees + balance changes)
  Step 4: Approve → loadSigner → buildSendSOL → submitViaJito
  Step 5: ConfirmationTracker polls until finalized
```

Swap and Stake flows follow the same pattern with different builders.

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
| `swap` | `input_mint`, `output_mint`, `amount`, `slippage_bps?` | Jupiter swap |
| `stake` | `lst_mint`, `amount` | Sanctum liquid staking |
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
| Sanctum | Liquid staking quotes + txs | `SanctumClient` |
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
Cloud Agent → Bridge (FastAPI, port 9877) → localhost:9876 (Swift app)
```

The bridge is a transparent HTTP proxy. Same auth token, same endpoints. Keys never leave the user's machine. The bridge forwards requests and polls status on behalf of remote agents.

**Run:** `deadbolt-bridge` (pip install from `bridge/`)
**Config:** Same `~/.deadbolt/config.json` or env vars (`DEADBOLT_API_TOKEN`, `DEADBOLT_UPSTREAM_URL`)

---

## Build & Run

```bash
# Swift app (macOS)
cd DeadboltWallet && swift build

# Unit tests
swift test --package-path Packages/DeadboltCore

# Integration tests (app must be running)
./tests/test_intent_api.sh

# Bridge
cd bridge && pip install -e . && deadbolt-bridge

# ESP32 firmware
# Open firmware/unruggable_esp32/unruggable_esp32.ino in Arduino IDE
# Board: ESP32-C3, upload via USB
```
