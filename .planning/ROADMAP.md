# Roadmap: Deadbolt

## Overview

Deadbolt's existing codebase has the core components partially built — axum agent server, guardrails engine, ESP32 serial bridge, vault, signer — but critical wiring is missing. This milestone connects all the pieces: auth gates every sensitive operation, the agent API is exposed to Flutter via the FRB StreamSink bridge, the signing prompt surfaces agent intents to the user, guardrails enforce configurable transaction limits, the ESP32 firmware gains BIP39 recovery capability, and navigation plus polish complete the user-facing experience. The work is plumbing and hardening, not greenfield construction.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Auth System** - Wire vault unlock and app password gate into Flutter UI with idle auto-lock (completed 2026-03-16)
- [x] **Phase 2: Agent API Bridge** - Expose the existing axum server to Flutter via FRB StreamSink and add key management UI (completed 2026-03-17)
- [x] **Phase 3: Agent Signing Prompt** - Build the dismissable overlay, intent queue, simulation results, and full lifecycle tracking (completed 2026-03-18)
- [x] **Phase 4: Guardrails Engine** - Harden the existing Rust guardrails with atomic concurrency, persistence, and Flutter settings UI (completed 2026-03-19)
- [ ] **Phase 5: ESP32 Firmware Rewrite** - Rewrite firmware for BIP39 mnemonic generation and secure NVS storage, with Flutter backup flow
- [ ] **Phase 6: Navigation, Settings, and Polish** - Add sidebar entries, settings sections, wallet rename, and UX polish items

## Phase Details

### Phase 1: Auth System
**Goal**: Users must authenticate to use the wallet, and all sensitive operations require the app password
**Depends on**: Nothing (first phase)
**Requirements**: AUTH-01, AUTH-02, AUTH-03, AUTH-04, AUTH-05, AUTH-06, AUTH-07, AUTH-08, INFR-06, INFR-07
**Success Criteria** (what must be TRUE):
  1. User must enter app password to launch the app; incorrect password is rejected and wallet data remains locked
  2. Wallet auto-locks after the configured idle period; re-entry requires the app password
  3. Attempting to reveal the mnemonic, create/delete an API key, or approve a transaction without unlocking shows an auth challenge
  4. User can change their app password from settings and the new password works on next lock/unlock
  5. Rust vault's AtomicBool `locked` flag gates all in-flight signing calls; a call in-progress at lock time returns WalletLocked error
**Plans:** 5/5 plans complete

Plans:
- [ ] 01-01-PLAN.md — Rust auth module (password hash + AtomicBool lock gate) and FFI bridge
- [ ] 01-02-PLAN.md — INFR-06 constant-time token comparison + INFR-07 zeroization audit
- [ ] 01-03-PLAN.md — Flutter AuthProvider, lock screen UI, GoRouter redirect, idle timer
- [ ] 01-04-PLAN.md — Onboarding password step + password strength meter
- [ ] 01-05-PLAN.md — Auth challenge dialog + Settings security section + end-to-end verification

### Phase 2: Agent API Bridge
**Goal**: The embedded axum HTTP server is running, connected to Flutter via FRB, and AI agents can authenticate and query wallet data
**Depends on**: Phase 1
**Requirements**: AGNT-01, AGNT-02, AGNT-10, AGNT-11, AGNT-12, AGNT-13, AGNT-14, AGNT-15, INFR-05, INFR-08
**Success Criteria** (what must be TRUE):
  1. User can toggle the agent server on from settings; a status indicator shows running/stopped/error state in real time
  2. An AI agent hitting localhost:9876 with a valid bearer token receives wallet, balance, tokens, price, and history responses without any user approval
  3. User can create an API key (shown once, then masked), copy it, and revoke it from the Agent API settings screen
  4. The quick-test section displays a ready-to-paste curl command using the user's real API token
  5. Closing the app cleanly shuts down the HTTP server; next launch can bind port 9876 without an "address in use" error
**Plans:** 4/4 plans complete

Plans:
- [ ] 02-01-PLAN.md — Rust server: WalletDataSnapshot, query handlers (/balance, /tokens, /price, /history), SO_REUSEADDR, AppConfig labels
- [ ] 02-02-PLAN.md — FRB bridge agent.rs: server start/stop, API key CRUD, wallet data updates
- [ ] 02-03-PLAN.md — Flutter providers, NavigationRail 5th entry, GoRouter /agent-api, window close lifecycle
- [ ] 02-04-PLAN.md — Agent API screen UI (server toggle, key management, quick test curl) + human verification

### Phase 3: Agent Signing Prompt
**Goal**: AI agents can POST transaction intents and users review, simulate, approve, or reject them through a non-blocking overlay
**Depends on**: Phase 2
**Requirements**: AGNT-03, AGNT-04, AGNT-05, AGNT-06, AGNT-07, AGNT-08, AGNT-09
**Success Criteria** (what must be TRUE):
  1. An agent POSTing a send_sol, send_token, swap, or sign_message intent causes a dismissable overlay to appear with full transaction preview
  2. Intents received while the user is away accumulate in a queue; returning user sees all pending intents and can approve or reject each
  3. Transaction simulation runs in the background; the signing prompt updates in place when simulation results arrive
  4. Approving an intent causes the transaction to be built, signed (software or hardware wallet), and submitted; the agent can poll the intent status through to confirmed/failed/rejected
  5. Rejecting an intent returns a structured rejection error to the polling agent immediately
**Plans:** 6/6 plans complete

Plans:
- [ ] 03-01-PLAN.md — Rust IntentType SignMessage + FRB bridge intent functions + Dart stubs
- [ ] 03-02-PLAN.md — Dart intent model + IntentNotifier with signing pipeline + navigator key
- [ ] 03-03-PLAN.md — Signing prompt bottom sheet + queue section + NavigationRail badge + auto-show
- [ ] 03-04-PLAN.md — E2E human verification of full signing prompt system
- [ ] 03-05-PLAN.md — Gap closure: sign_message bridge function + Dart signing pipeline wiring
- [ ] 03-06-PLAN.md — Gap closure: unsigned tx builders + background simulation wiring

### Phase 4: Guardrails Engine
**Goal**: Configurable transaction guardrails enforce user-defined limits on all transactions — agent and manual — with bypass requiring the app password
**Depends on**: Phase 1
**Requirements**: GRDL-01, GRDL-02, GRDL-03, GRDL-04, GRDL-05, GRDL-06, GRDL-07, INFR-04
**Success Criteria** (what must be TRUE):
  1. User can configure a token whitelist and program whitelist from settings; transactions involving non-whitelisted tokens or programs are blocked
  2. When a transaction is blocked by a guardrail, the agent receives a specific human-readable error message identifying which limit was exceeded
  3. User can bypass a guardrail block by entering the app password; the bypass window has a hard timeout
  4. Guardrail state (whitelists) survives app restart; previously configured limits are active on next launch without re-entry
  5. Guardrails apply equally to agent-initiated and manually sent transactions from the send screen
**Plans:** 4/4 plans complete

Plans:
- [ ] 04-01-PLAN.md — Rust core: enabled field, swap output_mint fix, check_token_whitelist, FRB bridge module, fix server config
- [ ] 04-02-PLAN.md — Flutter FRB stub, GuardrailsNotifier provider, GuardrailsSettingsSection with token whitelist UI
- [ ] 04-03-PLAN.md — Send/swap enforcement: guardrail fields in state, provider checks, inline violation banners with bypass
- [ ] 04-04-PLAN.md — End-to-end human verification of complete guardrails system

### Phase 5: ESP32 Firmware Rewrite
**Goal**: The ESP32 firmware generates BIP39 mnemonics from verified entropy, stores seeds securely, and Flutter guides the user through backup
**Depends on**: Nothing (independent track, can run in parallel with Phases 1-4)
**Requirements**: HWLT-01, HWLT-02, HWLT-03, HWLT-04, HWLT-05, HWLT-06, INFR-01, INFR-02, INFR-03
**Success Criteria** (what must be TRUE):
  1. User can trigger new keypair generation on the ESP32; the app displays the BIP39 mnemonic exactly once for the user to record
  2. On app launch, a previously paired ESP32 auto-connects silently; the Hardware Wallet sidebar entry reflects connected/disconnected status without user action
  3. When an ESP32 reconnects, the app verifies the device's pubkey matches the registered wallet address and surfaces a warning if it does not match
  4. The ESP32 firmware uses a verified hardware entropy source; the firmware fails loudly at runtime if entropy quality cannot be confirmed
  5. The ESP32 seed is stored encrypted in NVS; a factory reset erases the entire NVS partition rather than soft-deleting the key entry
**Plans**: TBD

### Phase 6: Navigation, Settings, and Polish
**Goal**: Sidebar navigation is complete, settings expose all new features, and UX polish items make the app feel finished
**Depends on**: Phase 2, Phase 5
**Requirements**: NAVS-01, NAVS-02, NAVS-03, NAVS-04, WLMT-01, PLSH-01, PLSH-02, PLSH-03, PLSH-04
**Success Criteria** (what must be TRUE):
  1. Hardware Wallet and Agent API sidebar entries are always visible; each guides setup if the feature is not yet configured
  2. Settings screen has a security section (password, timeout) and an agent API section (server toggle, guardrails link)
  3. User can rename any wallet; the new name appears immediately in the wallet drawer and all screens
  4. Cmd+R refreshes the dashboard; copied sensitive values auto-clear from clipboard after 30 seconds with a toast; all list screens show a minimal empty state
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order. Phase 5 is independent and may run in parallel with Phases 1-4.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Auth System | 5/5 | Complete   | 2026-03-16 |
| 2. Agent API Bridge | 4/4 | Complete   | 2026-03-17 |
| 3. Agent Signing Prompt | 6/6 | Complete   | 2026-03-18 |
| 4. Guardrails Engine | 4/4 | Complete    | 2026-03-19 |
| 5. ESP32 Firmware Rewrite | 0/TBD | Not started | - |
| 6. Navigation, Settings, and Polish | 0/TBD | Not started | - |

---
*Roadmap created: 2026-03-16*
*Last updated: 2026-03-19 after Phase 4 plans created*
