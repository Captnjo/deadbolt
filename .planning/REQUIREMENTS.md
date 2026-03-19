# Requirements: Deadbolt

**Defined:** 2026-03-16
**Core Value:** An AI agent can express intent and send transactions to Deadbolt for signing — through hardware wallet or hot wallet — with configurable guardrails the user controls.

## v1 Requirements

Requirements for this milestone. Each maps to roadmap phases.

### Authentication

- [x] **AUTH-01**: User must enter app password to unlock wallet on launch
- [x] **AUTH-02**: Wallet auto-locks after configurable idle timeout (default 15 min)
- [x] **AUTH-03**: User can configure idle timeout duration in settings
- [x] **AUTH-04**: App password required to reveal mnemonic phrase
- [x] **AUTH-05**: App password required to override guardrail blocks (not for regular transaction signing)
- [x] **AUTH-06**: App password required to create or delete an API key
- [x] **AUTH-07**: User can set and change app password in settings
- [x] **AUTH-08**: Password hash stored securely (scrypt-derived, not plaintext)

### Agent API

- [x] **AGNT-01**: Embedded HTTP server starts on localhost:9876 when user enables it
- [x] **AGNT-02**: Agent authenticates with bearer token (db_ prefix)
- [x] **AGNT-03**: Agent can POST intent (send_sol, send_token, swap, sign_message)
- [x] **AGNT-04**: User sees dismissable signing prompt overlay with full preview when app is open
- [x] **AGNT-05**: Pending intents queue when user is away; user reviews queued list on return
- [x] **AGNT-06**: Transaction simulation runs in background; prompt updates with results
- [x] **AGNT-07**: User can approve or reject each intent from the signing prompt
- [x] **AGNT-08**: Approved intent is built, signed (software or hardware), and submitted
- [x] **AGNT-09**: Agent can poll intent status (pending → building → signing → submitted → confirmed/failed/rejected)
- [x] **AGNT-10**: Query endpoints available without approval: wallet, balance, tokens, price, history
- [x] **AGNT-11**: User can create API keys (shown once, then masked)
- [x] **AGNT-12**: User can revoke API keys
- [x] **AGNT-13**: Quick test section generates copy-paste curl command with user's real token
- [x] **AGNT-14**: Agent API has its own sidebar entry (always visible, guides setup if not configured)
- [x] **AGNT-15**: Server status indicator shows running/stopped state

### Guardrails

- [x] **GRDL-01**: User can configure token whitelist (allow-list of token mints agents can interact with)
- [x] **GRDL-02**: User can configure program whitelist (allow-list of programs agents can call)
- [ ] **GRDL-03**: Whitelists configurable via text field (mint address) and searchable picker from held tokens
- [x] **GRDL-04**: Guardrails apply to both agent-initiated and manual transactions
- [x] **GRDL-05**: When guardrail blocks a transaction, agent receives specific error message
- [ ] **GRDL-06**: User can bypass a guardrail block with app password (timed window)
- [ ] **GRDL-07**: Guardrails settings UI accessible from settings screen

### Hardware Wallet

- [ ] **HWLT-01**: Previously paired ESP32 silently auto-connects on app launch
- [ ] **HWLT-02**: UI updates connection status when ESP32 connects/disconnects
- [ ] **HWLT-03**: App verifies device pubkey matches registered wallet address on reconnect
- [ ] **HWLT-04**: User can generate new keypair on ESP32 with BIP39 mnemonic backup
- [ ] **HWLT-05**: Mnemonic displayed once during setup for user to write down
- [ ] **HWLT-06**: Hardware Wallet has its own sidebar entry (always visible, guides setup if not connected)

### Infrastructure Rebuilds

- [ ] **INFR-01**: ESP32 firmware supports BIP39 mnemonic generation and SLIP-0010 key derivation
- [ ] **INFR-02**: ESP32 firmware uses verified entropy source (not silently weak esp_random)
- [ ] **INFR-03**: ESP32 seed stored encrypted in NVS (not plaintext)
- [x] **INFR-04**: Guardrail state (whitelists) persisted to disk, survives app restart
- [x] **INFR-05**: Axum server migrated to 0.8 route syntax
- [x] **INFR-06**: Bearer token comparison uses constant-time equality (prevent timing attack)
- [x] **INFR-07**: Zeroization audit: all key material on heap (Box/SecretVec), no stack copies
- [x] **INFR-08**: Axum server properly shuts down on app close (no orphaned port)

### Navigation & Settings

- [ ] **NAVS-01**: Hardware Wallet sidebar entry added (always visible)
- [ ] **NAVS-02**: Agent API sidebar entry added (always visible)
- [ ] **NAVS-03**: Settings screen includes security section (password, timeout)
- [ ] **NAVS-04**: Settings screen includes agent API section (server toggle, guardrails link)

### Wallet Management

- [ ] **WLMT-01**: User can rename a wallet (updates display name in config)

### Polish

- [ ] **PLSH-01**: Cmd+R refreshes dashboard on macOS
- [ ] **PLSH-02**: Clipboard auto-clears after 30 seconds with toast notification
- [ ] **PLSH-03**: All list screens show minimal empty state ("No items yet")
- [ ] **PLSH-04**: Jito bundle submission verified working end-to-end on mainnet

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Authentication

- **AUTH-V2-01**: Touch ID / biometric as optional unlock method (via local_auth)
- **AUTH-V2-02**: Biometric-only mode (no password)

### Guardrails

- **GRDL-V2-01**: Per-transaction SOL and USD limits
- **GRDL-V2-02**: Daily transaction count and USD spend limits
- **GRDL-V2-03**: Cooldown between agent transactions
- **GRDL-V2-04**: Guardrail state persistence to SQLite for daily counters

### Wallet Management

- **WLMT-V2-01**: Import wallet from Solana CLI keypair file (64-byte JSON array)
- **WLMT-V2-02**: Vanity address generation (prefix grinding)

### Hardware Wallet

- **HWLT-V2-01**: Derive multiple public keys from same ESP32 seed
- **HWLT-V2-02**: ESP32 setup verification quiz (confirm mnemonic words)

### Agent API

- **AGNT-V2-01**: Batch intents (multiple intents approved atomically)
- **AGNT-V2-02**: Long-poll /subscribe endpoint for near-real-time status updates
- **AGNT-V2-03**: Remote bridge service (Python FastAPI proxy for cloud agents)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Ledger hardware wallet support | ESP32 is the hardware path; Ledger adds complexity without core value |
| Quantum-resistant vaults (Winternitz) | Interesting but not core to agent signing goal |
| SNS / ANS domain name resolution | Nice-to-have, not v1 |
| Multisig (Squads v4) | Different use case entirely |
| Bulk send | Not core to agent signing flow |
| Lending / yield farming | Not core |
| Mobile platforms (iOS/Android) | Desktop first, macOS primary |
| Browser extension | Native app by design (agent API needs port binding) |
| Remote bridge service | Exists in repo, deferred to v2 |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| AUTH-01 | Phase 1 | Complete |
| AUTH-02 | Phase 1 | Complete |
| AUTH-03 | Phase 1 | Complete |
| AUTH-04 | Phase 1 | Complete |
| AUTH-05 | Phase 1 | Complete |
| AUTH-06 | Phase 1 | Complete |
| AUTH-07 | Phase 1 | Complete |
| AUTH-08 | Phase 1 | Complete |
| AGNT-01 | Phase 2 | Complete |
| AGNT-02 | Phase 2 | Complete |
| AGNT-03 | Phase 3 | Complete |
| AGNT-04 | Phase 3 | Complete |
| AGNT-05 | Phase 3 | Complete |
| AGNT-06 | Phase 3 | Complete |
| AGNT-07 | Phase 3 | Complete |
| AGNT-08 | Phase 3 | Complete |
| AGNT-09 | Phase 3 | Complete |
| AGNT-10 | Phase 2 | Complete |
| AGNT-11 | Phase 2 | Complete |
| AGNT-12 | Phase 2 | Complete |
| AGNT-13 | Phase 2 | Complete |
| AGNT-14 | Phase 2 | Complete |
| AGNT-15 | Phase 2 | Complete |
| GRDL-01 | Phase 4 | Complete |
| GRDL-02 | Phase 4 | Complete |
| GRDL-03 | Phase 4 | Pending |
| GRDL-04 | Phase 4 | Complete |
| GRDL-05 | Phase 4 | Complete |
| GRDL-06 | Phase 4 | Pending |
| GRDL-07 | Phase 4 | Pending |
| HWLT-01 | Phase 5 | Pending |
| HWLT-02 | Phase 5 | Pending |
| HWLT-03 | Phase 5 | Pending |
| HWLT-04 | Phase 5 | Pending |
| HWLT-05 | Phase 5 | Pending |
| HWLT-06 | Phase 5 | Pending |
| INFR-01 | Phase 5 | Pending |
| INFR-02 | Phase 5 | Pending |
| INFR-03 | Phase 5 | Pending |
| INFR-04 | Phase 4 | Complete |
| INFR-05 | Phase 2 | Complete |
| INFR-06 | Phase 1 | Complete |
| INFR-07 | Phase 1 | Complete |
| INFR-08 | Phase 2 | Complete |
| NAVS-01 | Phase 6 | Pending |
| NAVS-02 | Phase 6 | Pending |
| NAVS-03 | Phase 6 | Pending |
| NAVS-04 | Phase 6 | Pending |
| WLMT-01 | Phase 6 | Pending |
| PLSH-01 | Phase 6 | Pending |
| PLSH-02 | Phase 6 | Pending |
| PLSH-03 | Phase 6 | Pending |
| PLSH-04 | Phase 6 | Pending |

**Coverage:**
- v1 requirements: 53 total
- Mapped to phases: 53
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-16*
*Last updated: 2026-03-16 after roadmap creation — all 53 requirements mapped*
