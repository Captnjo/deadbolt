# Deadbolt

A cross-platform Solana wallet with ESP32 hardware signer support and an embedded agent API. Built with Flutter (UI) and Rust (crypto, signing, transaction building). Private keys never leave Rust.

## What It Does

- **Cross-platform wallet** — Flutter + Rust app targeting macOS, Windows, Linux, iOS, and Android. Send SOL/tokens, Jupiter/DFlow swaps, Jito MEV protection.
- **ESP32 hardware signing** — Ed25519 keys never leave the $5 microcontroller. Press a physical button to approve every transaction.
- **Agent signing gateway** — AI agents POST structured intents via REST API. The wallet builds and previews transactions; the user approves with a button press.
- **Configurable guardrails** — Per-transaction limits, daily caps, token/program whitelists, cooldowns. Enforced at the Rust signing layer — cannot be bypassed.
- **Full preview before every signature** — Balance changes, fees, simulation results, and warnings.

## Architecture

```
AI Agents (any framework)
    |
    | REST API (localhost:9876)
    v
Flutter UI (Dart)                    Rust Core (deadbolt_core)
┌──────────────────────┐             ┌──────────────────────────┐
│ Riverpod state       │             │ Ed25519 signing          │
│ GoRouter navigation  │◄────FFI────►│ BIP39 mnemonic           │
│ HTTP clients         │             │ ChaCha20-Poly1305 vault  │
│ Brand theme          │             │ Solana tx builder        │
└──────────────────────┘             │ Platform secure storage  │
                                     │ ESP32 serial bridge      │
                                     │ Agent API (axum)         │
                                     │ Guardrails engine        │
                                     └──────────────────────────┘
                                                  |
                                     ┌────────────┴────────────┐
                                     │                         │
                              Software signer          ESP32 hardware
                              (vault decrypt)          (USB serial)
                                     |                         |
                                     └─────────┬───────────────┘
                                               v
                                    Solana (Helius RPC + Jito)
```

### Signing Paths

Two backends behind the `TransactionSigner` trait:

- **Software wallet** — Rust decrypts vault, signs with `ed25519-dalek`, submits
- **ESP32 hardware** — Rust builds tx, sends bytes over USB serial, ESP32 signs with physical button, Rust attaches signature and submits

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
  theme/                 # Brand colors + ThemeData
  routing/               # GoRouter (sidebar desktop, tabs mobile)
  providers/             # Riverpod notifiers (wallet, balance, network, emoji)
  services/              # HTTP clients (RPC, Helius, price)
  features/
    dashboard/           # Portfolio view (SOL + token balances, USD values)
    send/                # Send flow (simulation, fee estimation, inline review)
    receive/             # QR code + address copy
    swap/                # Jupiter/DFlow swap flow
    wallet/              # Wallet management (create, import, hardware)
    history/             # Transaction history (Helius Enhanced API)
    address_book/        # Contact management
    nft/                 # Send NFT flow
    settings/            # Network, API keys, preferences
    onboarding/          # First-run wizard
  shared/                # App shell, title bar, wallet drawer, formatters, widgets

DeadboltWallet/          # Legacy Swift macOS app (superseded by Flutter)
firmware/                # ESP32 Arduino firmware for hardware signing
bridge/                  # Python FastAPI service for remote agent access
calypso/                 # Legacy Node.js transaction modules
```

## Requirements

- **Flutter SDK** ^3.11
- **Rust** stable toolchain
- **macOS 13+** (for macOS target)
- **Helius API key** — configured in Settings

For hardware wallet:
- **ESP32 dev board** (any with USB-serial, ~$5)
- USB cable

## Build & Run

```bash
git clone https://github.com/Captnjo/deadbolt.git
cd deadbolt

# Install dependencies
flutter pub get

# Run in debug mode
flutter run -d macos

# Release build
flutter build macos
open build/macos/Build/Products/Release/deadbolt.app
```

The Rust crate compiles automatically via `flutter_rust_bridge` during the Flutter build.

### Run Tests

```bash
# Rust core tests
cd rust/deadbolt_core
cargo test

# Flutter tests
flutter test
```

### ESP32 Firmware

Flash `firmware/unruggable_esp32/unruggable_esp32.ino` to your ESP32 using Arduino IDE or PlatformIO.

## Vault Security

Seeds are encrypted at rest with ChaCha20-Poly1305. The encryption key is derived via scrypt from a user password and cached in platform secure storage.

```
Seed → ChaCha20-Poly1305(scrypt(password, salt)) → ~/.deadbolt/vault/<address>.vault
```

| Platform | Secure Storage | Hardware-Backed |
|----------|---------------|-----------------|
| macOS | Keychain Services | Yes (Secure Enclave) |
| iOS | Keychain Services | Yes (Secure Enclave) |
| Windows | DPAPI + Credential Manager | Yes (TPM when available) |
| Linux | Secret Service (GNOME Keyring / KDE Wallet) | No |

Seeds are zeroized from memory on lock. The ESP32 path is the only signing method where the private key never touches the host device.

## Agent API

Embedded HTTP server on `localhost:9876`. AI agents POST transaction intents; the user sees a signing prompt with full preview and approves or rejects.

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
| `swap` | Jupiter/DFlow swap |
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

`pending_approval` → `building` → `signing` → `submitted` → `confirmed` | `rejected` | `failed`

## Guardrails

Configurable in Settings. Enforced at the Rust signing layer before any transaction is signed.

| Rule | Default |
|------|---------|
| Max SOL per transaction | 10 SOL |
| Max USD per transaction | $1,000 |
| Daily transaction limit | 50 |
| Daily USD limit | $5,000 |
| Token whitelist | SOL, USDC, USDT (empty = allow all) |
| Program whitelist | System, Token, Jupiter |
| Cooldown between txs | 5 seconds |

Because Deadbolt owns the signing key, guardrails cannot be bypassed — unlike a wrapper around an external wallet.

## Hardware Wallet (ESP32)

JSON serial protocol over USB:

| Command | Request | Response |
|---------|---------|----------|
| Ping | `{"cmd":"ping"}` | `{"status":"ok","msg":"pong"}` |
| Get pubkey | `{"cmd":"pubkey"}` | `{"status":"ok","pubkey":"<hex>","address":"<base58>"}` |
| Sign | `{"cmd":"sign","payload":"<hex>"}` | `{"status":"signed","signature":"<hex>"}` |

Sign flow: LED pulses, user presses BOOT within 30s, signature returned.

## License

See [LICENSE](LICENSE).
