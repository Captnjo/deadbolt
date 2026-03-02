# Deadbolt

A DIY hardware wallet for agentic DeFi on Solana. Built with commodity hardware (ESP32), open-source, and designed so AI agents can operate on-chain but never sign without human approval.

## What It Does

- **Native macOS wallet** — SwiftUI app with full Solana support: send SOL/tokens/NFTs, Jupiter swaps, Sanctum liquid staking, Jito MEV protection
- **ESP32 hardware signing** — Ed25519 keys never leave the $5 microcontroller. Press a physical button to approve every transaction
- **Agent signing gateway** — AI agents POST structured intents via REST API, the wallet builds and previews transactions, the user approves with a button press
- **Configurable guardrails** — Per-transaction limits, daily caps, token/program whitelists, cooldowns. Transactions that violate rules are auto-rejected before reaching the signing prompt
- **Full preview before every signature** — Balance changes, fees, simulation results, and warnings

## Architecture

```
AI Agents (any framework)
    |
    | REST API (localhost:9876 or external bridge)
    v
Deadbolt Swift App
    |
    |-- Intent Router --> Transaction Builder --> Guardrails Engine
    |                                                |
    |                               Signing Prompt (UI Modal)
    |                               Full preview + Approve/Reject
    |                                    |
    |                         Hot Wallet (CryptoKit)
    |                              or
    |                         Hardware Wallet (ESP32 Serial)
    v
Solana (via Helius RPC + Jito bundles)
```

## Project Structure

```
DeadboltWallet/          # Native macOS Swift app
  App/                   # SwiftUI app target
    Server/              # Embedded HTTP server (Hummingbird)
    Services/            # Guardrails, confirmation tracking, wallet management
    ViewModels/          # MVVM view models
    Views/               # SwiftUI screens
  Packages/
    DeadboltCore/        # Pure Swift library: crypto, RPC, transaction building
    HardwareWallet/      # ESP32 serial bridge (macOS only)

firmware/                # ESP32 Arduino firmware for hardware signing
bridge/                  # Python FastAPI service for remote agent access
calypso/                 # Legacy Node.js transaction modules
```

## Requirements

- **macOS 14+** (Sonoma or later)
- **Xcode 15+** / Swift 5.9+
- **Helius API key** — set `DEADBOLT_HELIUS_API_KEY` environment variable

For hardware wallet:
- **ESP32 dev board** (any with USB-serial, ~$5)
- USB cable

For the external bridge:
- **Python 3.10+**

## Build & Run

### macOS App

```bash
cd DeadboltWallet
swift build
```

Or open `DeadboltWallet/Package.swift` in Xcode and run the `DeadboltWallet` target.

### Run Tests

```bash
# Core library tests (342 tests)
cd DeadboltWallet/Packages/DeadboltCore
swift test

# Hardware wallet tests (17 tests)
cd DeadboltWallet/Packages/HardwareWallet
swift test
```

### ESP32 Firmware

Flash `firmware/unruggable_esp32/unruggable_esp32.ino` to your ESP32 using Arduino IDE or PlatformIO.

### External Bridge

```bash
cd bridge
pip install -e .
unruggable-bridge --port 9877
```

## Agent API

Agents interact via REST. Authenticate with a bearer token generated in Settings.

### Submit an Intent

```bash
curl -X POST http://localhost:9876/api/v1/intent \
  -H "Authorization: Bearer db_<your-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "swap",
    "params": {
      "input_mint": "So11111111111111111111111111111111111111112",
      "output_mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
      "amount": 1000000000,
      "slippage_bps": 50
    },
    "metadata": {
      "agent_id": "my-trading-bot",
      "reason": "DCA: weekly SOL to USDC"
    }
  }'
```

### Intent Types

| Intent | Description |
|--------|-------------|
| `send_sol` | Transfer SOL |
| `send_token` | Transfer SPL token |
| `swap` | Jupiter swap |
| `stake` | Sanctum liquid staking |
| `sign_message` | Sign an arbitrary message |
| `create_wallet` | Generate a new keypair |
| `batch` | Multiple intents, atomically approved |

### Query Endpoints (no approval needed)

| Endpoint | Description |
|----------|-------------|
| `GET /api/v1/wallet` | Active wallet info |
| `GET /api/v1/balance` | SOL + token balances |
| `GET /api/v1/tokens` | Token holdings with prices |
| `GET /api/v1/price?mint=` | Current token price |
| `GET /api/v1/history` | Recent transaction history |
| `GET /api/v1/status/:id` | Check intent status |

### Intent Lifecycle

`pending_approval` -> `building` -> `signing` -> `submitted` -> `confirmed` | `rejected` | `failed`

## Guardrails

Configurable in Settings. Transactions violating rules are auto-rejected.

| Rule | Default |
|------|---------|
| Max SOL per transaction | 10 SOL |
| Max USD per transaction | $1,000 |
| Daily transaction limit | 50 |
| Daily USD limit | $5,000 |
| Token whitelist | SOL, USDC, USDT (empty = allow all) |
| Program whitelist | System, Token, Jupiter, Sanctum |
| Cooldown between txs | 5 seconds |

## Security

- Ed25519 keys stored in macOS Keychain (hot wallet) or on ESP32 (hardware wallet)
- Config file written with 0600 permissions
- Bearer token validated with constant-time comparison
- All RPC URLs enforce HTTPS (except localhost)
- Jupiter swap instructions validated against trusted program whitelist
- Transaction simulation before every signature
- Request expiry cleanup (1 hour)
- Rate limiting on SSE/long-poll connections

## Legacy CLI

The original Bash CLI (`deadbolt.sh`) and Node.js modules (`calypso/`) are still in the repo. The native macOS app supersedes them.

## License

See [LICENSE](LICENSE).
