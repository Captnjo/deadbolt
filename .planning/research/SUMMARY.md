# Project Research Summary

**Project:** Deadbolt
**Domain:** Solana desktop wallet — embedded agent API, ESP32 hardware signer, auth system, transaction guardrails
**Researched:** 2026-03-16
**Confidence:** MEDIUM-HIGH

## Executive Summary

Deadbolt is a macOS desktop Solana wallet with no direct competitor: it combines a localhost REST API for AI agents, a $5 ESP32-C3 hardware signer, configurable transaction guardrails, and standard biometric/password auth — all without external infrastructure. The existing codebase has the core components partially built (axum server, guardrails engine, ESP32 serial bridge, vault, signer), but critical wiring is missing: auth is not connected to the Flutter UI, the agent API is not exposed via the FRB bridge, and the ESP32 firmware generates keys without BIP39 or secure entropy. This milestone's work is plumbing and hardening, not greenfield construction.

The recommended approach follows a strict dependency order established by the architecture: auth must come before agent signing (or any sensitive operation can be called without a lock gate), the agent FRB bridge must come before the signing prompt overlay, and the ESP32 firmware rewrite is independent of the other tracks and can proceed in parallel. The `flutter_rust_bridge` v2 StreamSink pattern is the correct mechanism for pushing agent intents from Rust to Dart — this eliminates polling latency and is the architectural keystone of the agent signing flow. The guardrails engine requires both atomic check-and-deduct semantics (concurrent request race) and persistence across app restarts (daily limits are per-session without it), making those implementation details non-negotiable scope items, not polish.

The top risks are hardware and security-class: weak ESP32 entropy produces silently brute-forceable mnemonics, NVS wear leveling means "delete key" leaves flash-recoverable material, and in-memory-only guardrail state makes daily limits effectively useless. Each of these has a clean prevention strategy (bootloader_random_enable, NVS partition erase, JSON sidecar persistence) that must be addressed before shipping, not deferred. The remaining pitfalls — port lifecycle, bearer token timing attack, zeroization via stack copies — are medium-severity and map cleanly to specific phases where they should be addressed.

---

## Key Findings

### Recommended Stack

The existing codebase is Flutter 3.29+ / Rust stable / flutter_rust_bridge 2.11.1 / axum (partial) / tokio. Four additions are required for this milestone. For Flutter auth, `local_auth` 3.0.1 is the official Flutter team plugin providing Touch ID + password fallback via macOS LocalAuthentication — no separate PIN UI or storage coupling. For the axum server, the correct pattern is an async FRB function that runs the server on FRB's own multi-threaded tokio runtime (not a second runtime, which panics); the existing `server.rs` needs axum 0.8 + tower-http 0.6 + a custom `axum::middleware::from_fn` for runtime bearer token validation. For ESP32 firmware, `bip39` 2.2.2 (no_std + alloc, rust-bitcoin maintained) + `esp-hal` 1.0.0 (official Espressif, RISC-V, unstable feature gate required for USB-CDC) + hardware TRNG via getrandom custom backend is the correct stack. For guardrails, a custom `GuardrailsEngine` struct handles dollar-amount transaction limits (GCRA libraries count requests, not dollars); `governor` 0.10.4 via `tower-governor` is used only for HTTP-layer rate limiting as a secondary safety net.

**Core technologies:**
- `local_auth` 3.0.1: Flutter biometric + password auth — official plugin, no coupling to storage, graceful fallback when Touch ID unavailable
- `axum` 0.8 + `tower-http` 0.6: Agent HTTP server — already partially built; needs FRB async bridge exposure
- `bip39` 2.2.2: ESP32 BIP39 mnemonic generation — no_std + alloc, verified December 2025 release, zeroize feature available
- `esp-hal` 1.0.0: ESP32-C3 HAL — official Espressif, stable RISC-V support, USB-CDC under `unstable` feature gate
- Custom `GuardrailsEngine`: Transaction guardrails — dollar-amount logic cannot be delegated to GCRA crates
- `governor` 0.10.4 via `tower-governor`: HTTP endpoint rate limiting — protects against agent bugs, not the financial guardrail layer

**Critical version constraints:**
- `local_auth` 3.0.1 requires Flutter 3.29+ / Dart 3.7+. PROJECT.md states Flutter 3.11+ minimum — verify actual pubspec.yaml version before adopting 3.x. If below 3.29, use `local_auth` 2.3.0 instead.
- `axum` 0.8 changed route syntax from `/:id` to `/{id}`. Verify which version the existing `server.rs` targets before assuming compatibility.

### Expected Features

**Must have (table stakes):**
- App password / vault unlock at launch — vault is useless without a lock; scrypt KDF exists in Rust, UI is missing
- Auto-lock on idle timeout (1 min / 5 min / 15 min / 1 hr) — Phantom/Coinbase standard; configurable
- Biometric unlock (Touch ID + password fallback) — expected in 2025; graceful no-op when Touch ID unavailable
- Re-auth gate before sensitive operations (reveal mnemonic, create/revoke API key, delete wallet)
- ESP32 BIP39 mnemonic generation + display flow — hardware wallet has no value without a backup path
- Word-by-word verification quiz (3-5 words) — all major hardware wallets require this before marking backup complete
- Agent API server (localhost:9876, bearer token auth) — the core product differentiator
- Token management UI (create, revoke, copy, name + last-used) — API is unusable without key management
- Agent signing prompt (overlay + queue) with transaction simulation result — human-in-the-loop is non-negotiable
- Intent lifecycle tracking (pending → approved → submitted → confirmed/failed)
- Guardrails engine: per-tx SOL/USD limit, daily limit, cooldown, token whitelist, program whitelist
- Guardrail bypass with password + timeout
- Read-only query endpoints (balance, tokens, price, history) without approval gate

**Should have (competitive differentiators):**
- Localhost agent API with no cloud dependency — unique vs Turnkey/Privy which require external servers
- ESP32 as $5 hardware signer vs $50-200 Ledger/Trezor
- Specific error messages to agent on limit exceeded ("daily limit: $4,900/$5,000")
- Intent timeout auto-rejection with countdown in queue UI
- curl test command generator — developer UX reduces setup friction
- Device identity verification on ESP32 reconnect (prevent hardware swap attacks)
- Clipboard auto-clear (30s) after sensitive copy operations

**Defer (v2+):**
- Auto-approve within guardrails (opt-in) — needs trust baseline first; complex UX
- Per-API-key guardrail overrides — adds UI complexity; ship global defaults first
- Remote agent API via SSH tunnel — networking scope out of v1
- Ledger/Trezor integration — explicitly out of scope per PROJECT.md
- Mobile platform (iOS/Android) — desktop-first milestone

**Anti-features to avoid building:**
- Full autonomous signing without any human approval gate — catastrophic if agent is compromised
- Biometric-only auth with no password fallback — fails on machines without Touch ID
- One global guardrail shared across all API keys — single compromised agent exhausts the shared limit
- Cloud backup of seed phrase

### Architecture Approach

The system is three layers with two external connections. The Flutter UI layer (Riverpod providers + Auth Gate + Agent Prompt Overlay) communicates with the Rust bridge layer (`deadbolt_bridge`) exclusively via flutter_rust_bridge v2 FFI — sync calls, async calls, and StreamSink for Rust-to-Dart event push. The bridge layer calls into `deadbolt_core` (same process, direct Rust calls) which owns all business logic: the axum agent server, vault/crypto, guardrails engine, and ESP32 serial bridge. The two external connections are: localhost:9876 HTTP (AI agent via bearer token) and USB serial /dev/cu.* (ESP32-C3 firmware via JSON newline protocol). The StreamSink pattern is architecturally central — it is how agent intents flow from the axum server through mpsc channels to the Dart stream that triggers the approval overlay, eliminating polling entirely.

**Major components:**
1. `Auth Provider` (Dart/Riverpod) — session state, idle timer, lock-on-timeout; wraps `local_auth` for biometric; calls `verify_app_password` FRB function
2. `agent/server.rs` (Rust/axum) — HTTP server on localhost:9876; intent queue via mpsc; bearer token middleware; GuardrailsEngine check-and-deduct on every POST /intent
3. `api/agent.rs` (deadbolt_bridge) — NEW: FRB-exposed `start_agent_server`, `approve_intent`, `reject_intent`, and `subscribe_agent_events(StreamSink)` bridge functions
4. `agent/guardrails.rs` (Rust) — EXISTS but needs atomic check-and-deduct + persistence; GuardrailsEngine with Mutex over entire check+write operation
5. `crypto/vault.rs` (Rust) — EXISTS; needs `verify_app_password` + session token (`Mutex<Option<SessionToken>>`) + `locked: AtomicBool` for in-flight FFI gating
6. ESP32-C3 firmware — REWRITE: add `generate_bip39` / `get_mnemonic` / `derive_pubkey` serial commands; replace raw keygen with BIP39 + PBKDF2 + SLIP-0010; enable NVS encryption

### Critical Pitfalls

1. **ESP32 pseudo-random entropy without active entropy source** — `esp_random()` silently returns pseudo-random output when Wi-Fi/BT/SAR ADC are inactive; BIP39 entropy becomes brute-forceable. Prevention: call `bootloader_random_enable()` before entropy collection; fail loudly at runtime if entropy source cannot be confirmed active.

2. **Guardrail daily limit is per-session without persistence** — in-memory state resets on app close; $4,900 spend before close + relaunch = full $5,000 available again. Prevention: persist `GuardrailState` with date to JSON sidecar file in Rust; check date on load; reset to zero only if date has rolled over. This is scope, not polish.

3. **Concurrent agent requests bypass daily limit via race condition** — two simultaneous requests both read remaining budget before either writes the increment. Prevention: hold a single `Mutex<GuardrailState>` for the entire check-and-deduct operation; never release between check and write.

4. **Auth lock does not gate in-flight FFI calls** — idle timeout fires in Flutter UI, but a signing call already in-flight 50ms prior completes in Rust regardless. Prevention: `locked: AtomicBool` in Rust vault; every signing path checks it and returns `Err(WalletLocked)` before proceeding.

5. **Port 9876 held across app restarts** — macOS TIME_WAIT + no graceful shutdown leaves port occupied; next launch fails silently. Prevention: `SO_REUSEADDR` on TcpListener; `flutter_window_close` hook to send oneshot shutdown signal; surface `AddrInUse` error in the Agent API status indicator.

6. **Bearer token compared with `==` — timing attack on localhost** — string equality short-circuits; co-located malicious process can enumerate token prefix. Prevention: `subtle::ConstantTimeEq` or `constant_time_eq` crate in `auth.rs`; store `sha256(token)` not plaintext.

7. **NVS wear leveling prevents secure key erasure** — `nvs_erase_key()` marks entry free but does not zero underlying flash sector; raw dump recovers seed. Prevention: enable NVS encryption + flash encryption in sdkconfig; use `nvs_flash_erase()` on partition for factory reset, not individual key deletion.

---

## Implications for Roadmap

Based on the component dependency graph established in ARCHITECTURE.md and the pitfall-to-phase mapping in PITFALLS.md:

### Phase 1: Auth System (Rust + Flutter)

**Rationale:** Every subsequent feature requires a working auth gate. Adding auth after agent signing creates a security gap where any FFI call can be made without a lock check. This is the architecture's explicit build order constraint #1.

**Delivers:** App password at launch; vault unlock via scrypt (existing Rust, needs Flutter wiring); idle timeout auto-lock; biometric unlock via `local_auth`; session token in Rust (`Mutex<Option<SessionToken>>`); `locked: AtomicBool` gating all signing operations; re-auth gate for sensitive operations; configurable timeout settings UI.

**Addresses features:** App password/lock/timeout (P1), biometric unlock (P2), re-auth on sensitive ops (P1).

**Avoids pitfalls:** Auth lock not gating in-flight FFI calls (Pitfall 8); password stored in Dart state (Architecture Anti-Pattern 3); zeroization via stack copies (audit vault code during this phase).

**Research flag:** Standard patterns — Flutter idle timer + Riverpod state management + `local_auth` 3.0.1 are well-documented. No deep research phase needed. Verify actual Flutter SDK version in pubspec.yaml before adopting `local_auth` 3.x.

---

### Phase 2: Agent API Bridge Exposure

**Rationale:** The `AgentServer` exists in `deadbolt_core` but is unwired to FRB. This is the highest-priority missing piece per ARCHITECTURE.md (build order #2). The signing prompt overlay cannot be built until the StreamSink event stream is working. Guardrails UI can be built in parallel.

**Delivers:** FRB-exposed `start_agent_server` (async fn on FRB tokio runtime), `stop_agent_server`, `approve_intent`, `reject_intent`, `subscribe_agent_events(StreamSink<IntentEventDto>)` in `api/agent.rs`; bearer token middleware wired into axum Tower stack; `constant_time_eq` comparison for tokens; server status indicator in Flutter (running/stopped/error); port bind error surfaced to UI.

**Addresses features:** Agent API server + bearer token (P1); token management UI (P1); server status indicator (P1).

**Avoids pitfalls:** Bearer token timing attack (Pitfall 10); port 9876 already in use (Pitfall 4); Tokio runtime not shut down on close (Pitfall 5); sync runtime-within-runtime panic (Architecture Anti-Pattern 1); Dart polling instead of StreamSink (Architecture Anti-Pattern 2).

**Research flag:** Standard patterns — FRB v2 StreamSink and axum 0.8 async patterns are documented in official sources. Verify axum route syntax version in existing `server.rs` before assuming 0.8 compatibility.

---

### Phase 3: Agent Signing Prompt + Intent Lifecycle

**Rationale:** Depends on Phase 1 (auth gate must exist before approval prompt) and Phase 2 (StreamSink must work before overlay can receive intents). This is the user-facing delivery of the agent API — it makes the API actually usable.

**Delivers:** AgentPromptOverlay (dismissable, not blocking); pending intent queue with count badge; transaction simulation result shown in prompt (background Helius RPC, updates in-place when result arrives); approve/reject with structured error back to agent; intent lifecycle status (pending → approved → submitted → confirmed/failed); intent queue persistence to SQLite (survives crash/close); auto-reject pending intents older than configurable timeout; GET /intent/{id}/status polling endpoint for agents.

**Addresses features:** Agent signing prompt + queue (P1); intent lifecycle tracking (P1); transaction simulation in prompt (P1); query endpoints without approval (P1); specific guardrail error messages to agent (P1).

**Avoids pitfalls:** Intent queue lost on app close (Pitfall 9); guardrails not re-checked at approval time (Architecture Anti-Pattern 5); blocking approval modal (UX Pitfalls section); simulation cached too long (Performance Traps).

**Research flag:** Needs research — intent persistence schema (SQLite vs JSON), long-polling vs polling timeout behavior for agent connections, Helius simulation integration details.

---

### Phase 4: Guardrails Engine Hardening

**Rationale:** GuardrailsEngine exists in Rust but needs atomic concurrency semantics, persistence, and Flutter UI. Can be built in parallel with Phase 2/3 from the Rust side, but the UI requires Phase 1 auth to be complete. Separating this into its own phase prevents scope bleed and ensures the "looks done but isn't" checklist items are explicitly verified.

**Delivers:** Atomic check-and-deduct via single `Mutex<GuardrailState>` acquisition; daily spend persistence to JSON sidecar file with date-based reset; per-tx SOL/USD limit; daily limit (count + USD); cooldown between transactions; token whitelist + program whitelist; guardrail bypass with password + hard timeout; specific error messages returned to agent on limit exceeded; guardrails applied to manual send flow as well as agent requests; Guardrails Settings UI.

**Addresses features:** Guardrails engine (P1); guardrail bypass (P1); token + program whitelist (P1); specific error messages (P1).

**Avoids pitfalls:** Concurrent requests bypass daily limit (Pitfall 6); guardrail state lost on restart (Pitfall 7); guardrails not applied to manual sends (PITFALLS "Looks Done But Isn't" checklist); bypass with no timeout (Security Mistakes section).

**Research flag:** Standard patterns for the Rust implementation. USD price feed integration (for dollar-amount limits) needs scoping — confirm whether Helius or another source provides this and at what latency.

---

### Phase 5: ESP32 BIP39 Firmware Rewrite

**Rationale:** Fully independent of Phases 1-4 (depends only on existing serial protocol types in `hardware/esp32_bridge.rs`). Can run in parallel with earlier phases. Separated here because it is a distinct firmware track with its own toolchain (no_std Rust for RISC-V, `esp-hal`, hardware RNG), its own security pitfalls (entropy, NVS wear leveling), and its own testing harness (physical device required).

**Delivers:** `bip39` 2.2.2 + `esp-hal` 1.0.0 + `esp-alloc` + hardware TRNG via getrandom custom backend; new serial commands: `generate_bip39`, `get_mnemonic`, `derive_pubkey`; PBKDF2-HMAC-SHA512 seed derivation (2048 iterations); SLIP-0010 Ed25519 key derivation at `m/44'/501'/0'/0'`; NVS partition encryption + flash encryption enabled in sdkconfig; store 64-byte seed (not private key) in NVS; firmware BIP39 wordlist in flash (English only, ~7KB); mnemonic display flow + word verification quiz in Flutter (depends on firmware serial commands working).

**Addresses features:** ESP32 BIP39 mnemonic generation (P1); word verification quiz (P1); device identity verification on reconnect (P2); mnemonic backup confirmed state.

**Avoids pitfalls:** Pseudo-random entropy without active entropy source (Pitfall 1 — `bootloader_random_enable()` required); NVS wear leveling exposes seed material (Pitfall 2 — NVS encryption + partition erase on reset); serial protocol partial JSON framing ("Looks Done But Isn't" checklist).

**Research flag:** Needs research — esp-hal 1.0.0 USB Serial/JTAG under `unstable` feature gate needs verification in esp-hal docs/examples before starting. PBKDF2 compute time on ESP32-C3 at 160MHz needs profiling (estimated 5-15s — confirm acceptable UX). Verify heap requirements for bip39 with 32KB esp-alloc.

---

### Phase Ordering Rationale

- **Auth first** because `check_session_valid()` and `verify_app_password()` are called by every subsequent phase. Building agent signing before auth means there is a window where FFI calls bypass the lock gate entirely.
- **Agent bridge second** because the StreamSink event stream is the load-bearing architectural element. The signing prompt overlay, intent queue, and all agent-facing UX depend on it working correctly.
- **Signing prompt third** because it is the user-visible payoff of the agent API. It requires both the auth gate (Phase 1) and the event stream (Phase 2) to be in place.
- **Guardrails fourth** because the engine exists in Rust; the work is hardening (atomicity, persistence) and Flutter UI. It must be verified against manual sends as well as agent requests — this is a deliberate phase-end checklist item.
- **ESP32 in parallel** because it is fully independent. If firmware work can be parallelized with team capacity, it should be. The Flutter mnemonic backup UI (display + quiz) does depend on the firmware serial commands, so that Flutter work blocks on firmware completion.

---

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 3 (Agent Signing Prompt):** Intent persistence schema design; long-polling timeout behavior for agent connections; Helius `simulateTransaction` integration (RPC error handling, blockhash expiry windows).
- **Phase 5 (ESP32 Firmware):** esp-hal 1.0.0 USB Serial/JTAG stability under `unstable` feature gate; PBKDF2 compute time on ESP32-C3; heap sizing for bip39 with esp-alloc.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Auth):** Flutter Riverpod state + `local_auth` 3.0.1 + FRB sync session token are well-documented. Implementation is wiring, not discovery.
- **Phase 2 (Agent Bridge):** FRB v2 StreamSink and axum 0.8 async patterns are documented in official sources with working examples. The dedicated thread vs FRB tokio runtime decision is already resolved in STACK.md.
- **Phase 4 (Guardrails):** Custom Rust state machine with mutex + JSON sidecar persistence is straightforward. USD price feed source needs a one-line scoping decision, not a research phase.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | Core libs (axum 0.8, bip39 2.2.2, local_auth 3.0.1) verified via official sources. esp-hal 1.0.0 is confirmed released but USB-CDC under `unstable` needs hands-on verification. tower-governor version confirmed from README only (MEDIUM). |
| Features | MEDIUM-HIGH | Table stakes features verified against Phantom, Coinbase Wallet, Trezor, and Ledger patterns. Agent API + guardrails features are novel (no direct comparator) but grounded in academic paper (arxiv 2601.04583) and Helius/Coinbase developer docs. |
| Architecture | HIGH | Based on direct codebase inspection + FRB v2 official documentation. StreamSink pattern, tokio runtime sharing, and session token design are all verified against real code and official docs. Build order is derived from actual component dependencies. |
| Pitfalls | HIGH | Security/crypto pitfalls verified against official Espressif docs, real CVEs/PRs (Teleport #2482), and peer-reviewed sources. Race condition and persistence pitfalls are logic-based with working test strategies. |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **Flutter SDK version constraint:** `local_auth` 3.0.1 requires Flutter 3.29+. PROJECT.md says Flutter 3.11+. Check actual `flutter` SDK version in `pubspec.yaml` before Phase 1 starts. If below 3.29, use `local_auth` 2.3.0 with adjusted API.
- **axum route syntax in existing server.rs:** server.rs was written with an unknown axum version. Before Phase 2, check whether it uses `/:id` (pre-0.8) or `/{id}` (0.8+) syntax to determine if a migration is needed.
- **USD price feed source:** Guardrails dollar-amount limits require a price feed. Neither STACK.md nor FEATURES.md specifies the source (Helius, Jupiter price API, CoinGecko). Decide before Phase 4 scope is finalized.
- **DailyTracker persistence path:** STACK.md recommends `~/Library/Application Support/Deadbolt/` for the JSON sidecar file. Verify the existing Rust storage layer's platform path logic covers this before Phase 4.
- **ESP32-C3 USB-CDC under `unstable`:** Must be verified in esp-hal 1.0.0 docs/examples before Phase 5 begins. If not available, the serial communication path changes.

---

## Sources

### Primary (HIGH confidence)
- pub.dev/packages/local_auth — version 3.0.1, macOS support, Flutter 3.29+ minimum confirmed
- tokio.rs/blog/2025-01-01-announcing-axum-0-8-0 — axum 0.8 release, tokio runtime requirements
- docs.rs/bip39 — version 2.2.2, no_std + alloc, December 2025 release, zeroize feature
- github.com/esp-rs/esp-hal — 1.0.0 release October 2025, ESP32-C3 support confirmed
- cjycode.com/flutter_rust_bridge/guides/types/translatable/stream — FRB v2 StreamSink official docs
- docs.espressif.com/projects/esp-idf/en/stable/esp32c3/api-reference/system/random.html — ESP32-C3 RNG entropy source requirements (critical for Pitfall 1)
- docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/storage/nvs_flash.html — NVS wear leveling behavior (critical for Pitfall 2)
- docs.rs/zeroize + benma.github.io/2020/10/16/rust-zeroize-move.html — Rust stack-copy zeroization pitfall
- Direct codebase inspection: `rust/deadbolt_core/src/agent/`, `rust/deadbolt_bridge/src/api/`, `firmware/unruggable_esp32/`
- arxiv.org/html/2601.04583v1 — Autonomous Agents on Blockchains: Standards and Trust Boundaries (2026)
- helius.dev/blog/how-to-build-a-secure-ai-agent-on-solana — agent wallet patterns

### Secondary (MEDIUM confidence)
- developer.espressif.com/blog/2025/02/rust-esp-hal-beta — beta caveats, `unstable` feature gate
- github.com/tokio-rs/axum/discussions/2501 — dedicated OS thread pattern for axum in non-async contexts
- github.com/benwis/tower-governor — tower-governor 0.3 wraps governor for axum (version from README only)
- smashingmagazine.com/2026/02/designing-agentic-ai-practical-ux-patterns/ — agentic UX patterns
- github.com/gravitational/teleport/pull/2482 — constant-time bearer token comparison pattern

### Tertiary (LOW confidence / needs validation)
- tower-governor 0.3 version number — confirmed from README only; verify against crates.io before use in Phase 2

---

*Research completed: 2026-03-16*
*Ready for roadmap: yes*
