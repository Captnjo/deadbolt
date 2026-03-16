# Deadbolt

## What This Is

A cross-platform Solana wallet with ESP32 hardware signer support and an embedded agent API. Built with Flutter (UI) and Rust (crypto, signing, transaction building). AI agents POST structured intents via REST API; the user previews and approves transactions; the app signs with either a software wallet (encrypted vault) or a $5 ESP32 hardware signer. Private keys never leave Rust.

## Core Value

An AI agent can express intent and send transactions to Deadbolt for signing — through hardware wallet or hot wallet — with configurable guardrails the user controls.

## Requirements

### Validated

<!-- Shipped and confirmed working in current codebase. -->

- ✓ Dashboard with SOL + token balances, USD values, NFT gallery, quick actions — existing
- ✓ Network & RPC configuration (Helius, mainnet/devnet/testnet) — existing
- ✓ Receive screen with QR code and address copy — existing
- ✓ Send SOL/token flow with simulation, fee estimation, inline review — existing
- ✓ Swap flow with Jupiter and DFlow aggregators, debounced quotes — existing
- ✓ Send NFT flow via Helius DAS API — existing
- ✓ Transaction history with Helius enrichment, filtering, pagination — existing
- ✓ Address book CRUD with search — existing
- ✓ Onboarding wizard (create wallet, import mnemonic, connect hardware) — existing
- ✓ Multi-wallet management with emoji assignment — existing
- ✓ ESP32 detection and serial connection — existing
- ✓ Hardware wallet signing for send/swap (partial — tested working) — existing
- ✓ Rust crypto core: Ed25519, BIP39, SLIP-0010, Base58, transaction builder — existing (57 tests)
- ✓ Vault encryption: ChaCha20-Poly1305, scrypt KDF, platform secure storage backends — existing in Rust
- ✓ Brand theme (dark mode, Solar Flare orange, Onyx Black) — existing
- ✓ Sidebar navigation with wallet drawer — existing
- ✓ Settings: network, API keys, aggregator preference, Jito toggle, display currency — existing

### Active

<!-- Current scope. Building toward these. -->

- [ ] App password authentication at launch and after idle timeout
- [ ] Touch ID / biometric as optional unlock method
- [ ] Auth gate on sensitive operations (unlock vault, reveal mnemonic, sign tx, create/delete API key)
- [ ] Configurable idle timeout in settings
- [ ] ESP32 firmware upgrade: BIP39 mnemonic generation, seed backup, key derivation from seed
- [ ] ESP32 on-device keypair generation with mnemonic backup flow in app
- [ ] ESP32 silent auto-connect for previously paired devices
- [ ] ESP32 device identity verification (pubkey match on reconnect)
- [ ] Agent API embedded HTTP server (axum, localhost:9876) with FFI bridge to Flutter
- [ ] Agent API bearer token auth (db_ prefix)
- [ ] Agent API key management UI (create, revoke, copy)
- [ ] Agent signing prompt: dismissable overlay when app open, queued list for pending signatures
- [ ] Transaction simulation in background, prompt updates when simulation completes
- [ ] Agent intent lifecycle (pending → building → signing → submitted → confirmed/failed/rejected)
- [ ] Query endpoints (wallet, balance, tokens, price, history) — no approval needed
- [ ] Quick test curl command generator in Agent API settings
- [ ] Agent API sidebar entry (always visible, guides setup if not configured)
- [ ] Server status indicator (running/stopped)
- [ ] Guardrails engine: per-tx limits (SOL, USD), daily limits (count, USD), cooldowns
- [ ] Guardrails: token whitelist and program whitelist
- [ ] Guardrails apply to both agent and manual transactions
- [ ] Guardrail bypass with app password (with timeout if user inactive)
- [ ] Specific guardrail error messages to agent ("daily limit exceeded: $4,800/$5,000")
- [ ] Guardrails settings UI (limits, whitelists via text field + searchable picker)
- [ ] Import wallet from Solana CLI keypair file (64-byte JSON array)
- [ ] Rename wallet
- [ ] Vanity address generation (prefix grinding)
- [ ] Hardware Wallet sidebar entry (always visible, guides setup if not connected)
- [ ] Settings: security section (auth mode, timeout)
- [ ] Settings: agent API section (server toggle, guardrails link)
- [ ] Cmd+R to refresh dashboard (macOS)
- [ ] Clipboard auto-clear after 30s with toast notification
- [ ] Empty states for all list screens (minimal style)
- [ ] Jito bundle submission verification (currently partial)

### Out of Scope

<!-- Explicit boundaries. -->

- Ledger hardware wallet support — not needed for v1, ESP32 is the hardware path
- Quantum-resistant vaults (Winternitz) — interesting but not core to agent signing goal
- SNS / ANS domain name resolution — nice-to-have, not v1
- Multisig (Squads v4) — different use case
- Bulk send — not core
- Lending / yield farming — not core
- Mobile platforms (iOS/Android) — desktop first, macOS primary target
- Browser extension — native app by design (agent API needs port binding)
- Remote bridge service (Python FastAPI) — exists in repo but not in v1 scope

## Context

- Existing codebase with Flutter UI and Rust core connected via flutter_rust_bridge v2.11.1
- Legacy Swift macOS app (DeadboltWallet/) superseded by Flutter — retained for reference
- Legacy Node.js modules (calypso/) — superseded by Rust core
- ESP32 firmware based on Unruggable project (https://github.com/hogyzen12/unruggable)
- Arduino C firmware using JSON serial protocol — will need Rust rewrite for BIP39 support
- Rust agent module (server.rs, auth.rs, guardrails.rs, intent.rs) exists but is not yet exposed to Flutter via FFI bridge
- Vault + storage backends implemented in Rust (keychain, dpapi, secret_service) but wallet unlock/lock not wired in Flutter UI
- Previous AI agent built much of the codebase — quality needs verification before extending
- Testing on macOS desktop (no Touch ID on this machine)
- GitHub repo: https://github.com/Captnjo/deadbolt.git

## Constraints

- **Platform**: macOS primary target, desktop-only for v1
- **Tech stack**: Flutter 3.11+ (UI) + Rust stable (core) + flutter_rust_bridge 2.11.1 (FFI)
- **ESP32**: Must run on ESP32-C3 (~384KB RAM, 16MB flash) — firmware must fit
- **Security**: Private keys never leave Rust process (software) or ESP32 device (hardware)
- **Agent API**: localhost only, bearer token auth, no remote access in v1
- **Signing**: Ed25519 (Solana requirement), no delegation to external wallets

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Native app, not browser extension | Agent API needs port binding; ESP32 needs USB serial; zero infrastructure | ✓ Good |
| Flutter + Rust (not full Rust/Dioxus) | Flutter provides mature cross-platform UI; Rust handles all crypto securely | ✓ Good |
| JSON serial protocol for ESP32 | Cleaner than text-based; already matches Rust bridge code | — Pending |
| Single password for vault + app lock | Simpler UX, one password to remember, scrypt makes it strong | — Pending |
| Guardrails on both agent and manual txs | Consistent safety; user can bypass with password | — Pending |
| ESP32 firmware rewrite for BIP39 | Required for mnemonic backup; current firmware generates raw keypairs with no recovery | — Pending |
| Dismissable overlay + queue for agent signing | Non-blocking when user is active; nothing lost when user is away | — Pending |

---
*Last updated: 2026-03-16 after initialization*
