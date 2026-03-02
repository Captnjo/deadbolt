# Deadbolt macOS Native App — Specification

## Context

Deadbolt is currently a Bash CLI wallet for Solana with Node.js transaction modules and ESP32 hardware wallet support. This spec defines the rewrite as a native macOS app in Swift/SwiftUI, adding transaction simulation and parsing via the Helius Enhanced Transactions API.

## Goals

- Native macOS app with SwiftUI GUI — no Electron, no web views
- Full feature parity with the existing CLI
- New: transaction parser + simulator (Helius SDK) — preview every transaction before signing
- New: transaction history with human-readable descriptions
- ESP32 hardware wallet support carried forward
- iOS-portable architecture (SwiftUI, avoid macOS-only APIs where possible)
- Progressive migration: rewrite core in Swift, keep Node.js modules as fallback during development

---

## Architecture

### Package Structure

```
DeadboltWallet/
  App/                          # macOS app target
    DeadboltApp.swift         # @main entry
    Views/                      # SwiftUI screens
    ViewModels/                 # MVVM view models
    Services/                   # App-level orchestration
  Packages/
    DeadboltCore/             # Platform-agnostic Swift Package
      Crypto/                   # Ed25519, Keychain, Base58
      Solana/                   # Transaction types, serialization, programs
      Network/                  # RPC, Helius, Jupiter, Sanctum, Jito clients
      Models/                   # Domain models (Wallet, Token, NFT, etc.)
      DataStore/                # Persistence (tokens, address book, config)
    HardwareWallet/             # macOS-only: ESP32 USB serial via ORSSerialPort
    NodeBridge/                 # Temporary: shell out to existing JS modules
```

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Ed25519 | Apple CryptoKit `Curve25519.Signing` | First-party, RFC 8032 compliant, no dependency. Accepts 32-byte seed from existing keypair files. |
| Solana SDK | Custom minimal implementation | Only need SystemProgram, ComputeBudget, SPL Token instructions + transaction serialization. Full SDK is overkill. |
| USB Serial | ORSSerialPort (Swift Package) | Most mature macOS serial lib. Isolated in its own package for iOS exclusion. |
| State | SwiftUI MVVM (`@StateObject`, `@EnvironmentObject`) | Simple enough for this app. No TCA/Redux needed. |
| Key storage | macOS Keychain (`kSecClassGenericPassword`) | OS-level encryption, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` prevents iCloud sync. |
| Node.js fallback | `Foundation.Process` to shell out | Temporary during migration. Each feature gets native Swift, then JS fallback removed. |
| Transaction preview | Local instruction analysis + `simulateTransaction` RPC | Parse our own instructions (we know what they do) + optional RPC simulation for validation. |

### Data Flow

```
SwiftUI View → ViewModel → Service Layer
                              ↓
                    ┌─────────┴──────────┐
                    │                    │
              Swift Core           NodeBridge (fallback)
              (DeadboltCore)     (Process → node script)
                    │
              ┌─────┴──────┐
              │            │
        Network Layer   SigningService
        (URLSession)        │
              │        ┌────┴────┐
              │   Software    Hardware
              │   (CryptoKit) (ESP32 Serial)
              │
        ┌─────┴──────────┐
        │    │    │    │
      Helius Jupiter Sanctum Jito
```

---

## Screens

### Dashboard (Home)
- Wallet address (with [HW WALLET] indicator when ESP32 connected)
- SOL balance + USD value
- Staked SOL balance + USD value
- Token list: name, balance, per-token price, USD value
- Total portfolio USD value
- Quick action toolbar

### Send SOL / Send Token / Send NFT
- **Step 1**: Recipient picker (manual address, wallet list, address book)
- **Step 2**: Amount entry (with max button, USD conversion)
- **Step 3**: Transaction preview (NEW)
  - Balance changes (SOL delta, token delta)
  - Fee breakdown (base fee + priority fee + tips)
  - Instruction summary ("Transfer 0.5 SOL to ABC...XYZ")
  - Simulation status (success/failure from `simulateTransaction`)
  - Warnings (unfunded recipient, large amount, etc.)
  - Approve / Cancel buttons
  - If hardware wallet: "Press BOOT button on ESP32" prompt
- **Step 4**: Confirmation tracker (Submitted → Confirmed → Finalized)

### Swap (Jupiter)
- Input token + amount
- Output token
- Quote display: rate, minimum received, slippage, route
- Transaction preview (same as above)
- Confirmation tracker

### Liquid Staking (Sanctum)
- SOL amount input
- LST output display (bonkSOL amount, rate)
- Transaction preview
- Confirmation tracker

### Native Staking
- SOL amount to stake
- Validator selection
- Existing stake account list with balances

### Receive
- Wallet address displayed
- QR code
- Copy button

### Transaction History (NEW)
- Paginated list from Helius Enhanced Transactions API
- Each row: type icon, human-readable description, timestamp, amount
- Expandable detail: full transfer breakdown, account changes, fee info
- Filter by type (transfers, swaps, staking, etc.)

### Wallet Management
- List all wallets (from `~/.config/solana/deadbolt/` and `~/.config/solana/`)
- Switch active wallet
- Create new wallet (vanity grind or seed phrase)
- Import from keypair file or seed phrase

### Address Book
- List entries (address + tag)
- Add / Edit / Delete
- Quick-select from send flows

### Settings
- RPC URL configuration (with validation)
- Hardware wallet: detect, connect, disconnect, status
- Active wallet display

---

## Transaction Parser + Simulator

### Pre-Sign Preview (every transaction)

Before the user signs any transaction, the app:

1. **Builds the transaction** with all instructions (transfer, compute budget, tips)
2. **Analyzes instructions locally** — we know what SystemProgram.transfer and SPL Token transfer do, so we can compute exact balance changes without an API call
3. **Calls `simulateTransaction` RPC** (optional, for validation) — confirms the transaction will succeed, returns compute units consumed
4. **Displays a structured preview**:
   ```
   Transaction Preview
   ───────────────────────────────
   Action:    Send 0.5 SOL
   To:        ABC...XYZ
   Fee:       ~0.000005 SOL
   Tips:      0.00084 SOL (Jito MEV protection)
   ───────────────────────────────
   Balance Changes:
     SOL:  -0.500845 SOL
   ───────────────────────────────
   Simulation: ✓ Will succeed (2,366 compute units)

   [Approve]  [Cancel]
   ```

### Post-Confirmation History

After transactions are confirmed, the app fetches parsed transaction data from the Helius Enhanced Transactions API:

- **Endpoint**: `https://api.helius.xyz/v0/transactions/?api-key={KEY}`
- **POST body**: `{ "transactions": ["<signature>"] }`
- **Returns**: Human-readable `description`, typed `nativeTransfers[]`, `tokenTransfers[]`, `events` (swap details, NFT sales, etc.)

This powers the Transaction History screen with rich, readable entries like:
- "Swapped 10 USDC for 0.067 SOL via Jupiter"
- "Transferred 1 Mad Lads #4521 to ABC...XYZ"
- "Staked 5 SOL with validator XYZ"

---

## External APIs

| Service | Endpoint | Purpose |
|---------|----------|---------|
| Helius RPC | `https://mainnet.helius-rpc.com/?api-key={KEY}` | Standard Solana RPC (blockhash, balance, simulate, etc.) |
| Helius Enhanced | `https://api.helius.xyz/v0/transactions/` | Transaction parsing |
| Helius DAS | via RPC `getAssetsByOwner` | Token + NFT metadata |
| Jupiter Quote | `https://quote-api.jup.ag/v6/quote` | Swap quotes |
| Jupiter Swap | `https://quote-api.jup.ag/v6/swap-instructions` | Swap instruction generation |
| Sanctum Quote | `https://api.sanctum.so/v1/swap/quote` | Liquid staking quotes |
| Sanctum Swap | `https://api.sanctum.so/v1/swap` | Pre-built staking transactions |
| Sanctum Price | `https://api.sanctum.so/v1/price` | LST exchange rates |
| Jito Transactions | `https://mainnet.block-engine.jito.wtf/api/v1/transactions` | MEV-protected transaction submission |
| Jito Bundles | `https://mainnet.block-engine.jito.wtf/api/v1/bundles` | Bundle submission (swap + tip) |

---

## Hardware Wallet (ESP32)

No firmware changes. The Swift app speaks the same JSON serial protocol:

| Command | Request | Response |
|---------|---------|----------|
| Ping | `{"cmd":"ping"}` | `{"status":"ok","msg":"pong"}` |
| Get pubkey | `{"cmd":"pubkey"}` | `{"status":"ok","pubkey":"<hex>","address":"<base58>"}` |
| Sign | `{"cmd":"sign","payload":"<hex msg bytes>"}` | `{"status":"pending",...}` then `{"status":"signed","signature":"<hex>"}` |
| Generate | `{"cmd":"generate"}` | `{"status":"ok","pubkey":"<hex>","address":"<base58>"}` |

Sign flow: LED pulses → user presses BOOT button within 30s → signature returned. If no press, `{"status":"error","msg":"rejected"}`.

The `TransactionSigner` protocol abstracts this:
```swift
protocol TransactionSigner {
    var publicKey: SolanaPublicKey { get }
    func sign(message: Data) async throws -> Data
}
```

Both `SoftwareSigner` (CryptoKit) and `ESP32SerialBridge` (ORSSerialPort) conform to this protocol. The rest of the app doesn't care which is active.

---

## Data Migration

The app reads existing CLI data files on first launch:
- `~/.config/solana/deadbolt/*.json` — keypair files → import to Keychain
- `~/.config/solana/deadbolt/tokens.txt` — token metadata
- `~/.config/solana/deadbolt/nfts.txt` — NFT metadata
- `~/.config/solana/deadbolt/addressBook.txt` — address book
- `~/.config/solana/cli/config.yml` — active wallet + RPC URL

After migration, the app uses Keychain for keys and its own data store for everything else. The CLI continues to work independently.

---

## Implementation Phases

| Phase | Scope | Depends On |
|-------|-------|------------|
| 1 | Foundation: Xcode project, Base58, keypair reader, CryptoKit Ed25519, Solana RPC client, Dashboard (balance display), Keychain storage | — |
| 2 | Send SOL: transaction serialization, SystemProgram, ComputeBudget, Jito submission, send UI, confirmation tracker | Phase 1 |
| 3 | Send Tokens + NFTs: SPL Token instructions, ATA derivation, token/NFT stores, send UI | Phase 2 |
| 4 | Jupiter Swaps: Jupiter API client, instruction deserialization, Legacy Transaction, swap UI | Phase 2 |
| 5 | Sanctum Liquid Staking: Sanctum API client, VersionedTransaction deserialization, Jito bundles, staking UI | Phase 2 |
| 6 | Hardware Wallet: ORSSerialPort, ESP32 serial bridge, device detection, signing integration | Phase 2 |
| 7 | Transaction Parser + Simulator: Helius Enhanced API, simulateTransaction, preview UI, history UI | Phase 2 |
| 8 | Wallet Management + Polish: create/import wallet, wallet switcher, address book, native staking, settings | Phase 1 |
| 9 | Remove Node.js fallback, comprehensive testing | All above |
| 10 | iOS preparation: audit platform-specific code, exclude HardwareWallet package | Phase 9 |

---

## Testing Strategy

- **Unit tests**: Ed25519 signature compatibility (Swift vs Node.js same-seed comparison), Base58 round-trips, transaction serialization byte comparison against known-good output, compact-u16 encoding edge cases
- **Integration tests**: Devnet transactions for each type, hardware wallet mock (simulated serial responses)
- **Manual testing checklist**: Every transaction type with both software and hardware signing, wallet creation/import/switch, address book operations, RPC error handling
