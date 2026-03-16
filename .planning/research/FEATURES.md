# Feature Research

**Domain:** Crypto wallet with embedded agent API, hardware signer (ESP32), and transaction guardrails
**Researched:** 2026-03-16
**Confidence:** MEDIUM-HIGH (core wallet patterns HIGH; agent API / ESP32-specific patterns MEDIUM due to novelty)

---

## Feature Landscape

### Table Stakes (Users Expect These)

These features are non-negotiable. Missing them means the product feels incomplete, broken, or unsafe. Users don't praise you for having them — they leave if you don't.

#### 1. App Authentication

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Password/PIN at launch | Every wallet app locks on open; no lock = unacceptable security | LOW | scrypt KDF already in Rust; UI only needed |
| Auto-lock after idle timeout | Standard behavior: Phantom, Coinbase, Trust Wallet all offer this | LOW | Configurable: Immediately / 1 min / 5 min / 15 min / 1 hour |
| Biometric unlock (Touch ID) | 34% of wallets offer biometrics in 2025; expected for desktop/mobile | MEDIUM | macOS: LocalAuthentication framework via FFI; fallback to password |
| Password required for sensitive ops | Re-authentication before: reveal mnemonic, delete wallet, change security settings | LOW | Google Wallet pattern: re-verify after timeout; Trust Wallet: passcode before send |
| Failed auth lockout | After N wrong attempts, delay or lock; standard brute-force protection | LOW | 3 attempts → exponential delay (KeepKey pattern); not hard lockout |

#### 2. Hardware Wallet / BIP39 Backup

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| On-device mnemonic generation | Hardware wallets must generate keys on-device, never in app | MEDIUM | Firmware rewrite required; entropy → SHA256 checksum → 11-bit groups → wordlist |
| Mnemonic display and write-down prompt | Every hardware wallet shows words one at a time with explicit "write these down" warning | LOW | Display 24 words with index (Word 1: abandon, Word 2: ...) |
| Word-by-word verification quiz | All major hardware wallets (Trezor, SafePal, Ledger) require confirming specific random words before continuing | LOW | Pick 3-5 random word positions; user selects correct word from list |
| Recovery/import from mnemonic | Standard BIP39 compatibility; users expect to restore from paper backup | MEDIUM | PBKDF2-HMAC-SHA512 with "mnemonic" salt, 2048 iterations → 512-bit seed |
| Device identity verification on reconnect | Re-verify pubkey matches on reconnect to prevent device swap attacks | LOW | Already planned; compare stored pubkey vs derived pubkey from hardware |
| Clear "backup not done" warning | Wallets with unbackedup keys must show persistent warning until backup confirmed | LOW | Banner/badge on hardware wallet UI until flow completed |

#### 3. Agent API Authentication

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Bearer token authentication | Standard REST API auth; every developer API uses this | LOW | Authorization: Bearer <token> header; db_ prefix for Deadbolt |
| Token shown only once at creation | Industry-wide security pattern (GitHub, Atlassian, Okta, Perplexity) | LOW | Show full token in dismissable modal; then only show masked version |
| Named tokens with creation date | Management pattern from Okta, Atlassian, GitHub; users need to identify which key is which | LOW | Name + created_at + last_used_at |
| Token revocation | Revoking access immediately is a hard requirement; compromised key must be killable | LOW | Immediate invalidation; no grace period |
| Server running/stopped indicator | API is a service; users need to know if it's accepting connections | LOW | Status dot in sidebar; show port number |

#### 4. Agent Signing Approval

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Explicit user approval for every transaction | Non-negotiable; agents must not sign autonomously without user review | MEDIUM | Dismissable overlay when app is open; queue for deferred review |
| Transaction simulation before approval prompt | Wallets like Solflare show simulation outcome before user commits; now standard | MEDIUM | Background simulation; update prompt when result arrives; show balance diff |
| Clear rejection with reason returned to agent | Agents must know why signing was rejected to handle errors; guessing is not acceptable | LOW | Structured error: {status: "rejected", reason: "user_declined"} |
| Pending queue with count badge | When user is away, intents accumulate; user needs to see "3 pending" on return | LOW | Badge on sidebar entry; list view of queued intents |
| Intent lifecycle status | Agents need to track state: pending → approved → submitted → confirmed / failed | MEDIUM | Webhook or polling endpoint; store status in DB |

#### 5. Guardrails

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Per-transaction SOL/USD limit | Core guardrail; "agent can't spend more than $100 per tx" is the base case | LOW | Compare tx amount * price against limit before signing |
| Daily spend limit (USD/count) | Standard spending control pattern; enterprise wallets and MPC providers all have this | MEDIUM | Rolling 24h window with running total; reset at UTC midnight or rolling |
| Specific limit-exceeded error messages to agent | Agent needs actionable errors ("daily limit exceeded: $4,800/$5,000") to log/retry/escalate | LOW | Structured error response with current usage + limit |
| Guardrails apply to manual transactions too | Consistency: if user clicks "Send" manually, limits still apply unless bypassed | LOW | Single guardrail engine called by both agent and manual send paths |
| Guardrail bypass with password | User can override any guardrail by entering password; bypass has a timeout window | MEDIUM | Password bypass creates a timed window (e.g., 5 min) before re-enforcing |

---

### Differentiators (Competitive Advantage)

These features set Deadbolt apart. They directly serve the core value: "AI agent + hardware wallet + configurable guardrails."

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Localhost agent API (no cloud required) | Unique: zero infrastructure, zero latency, no key exposure to third parties; existing cloud agents (Turnkey, Privy) require external servers | HIGH | axum HTTP server embedded in Rust; FFI bridge to Flutter for UI sync |
| ESP32 as a $5 hardware signer | Sub-$10 hardware security vs $50-$200 Ledger/Trezor; DIY/maker appeal | HIGH | Firmware BIP39 rewrite; JSON serial protocol; device identity verification |
| Agent intent lifecycle API | Most wallets don't expose a signing lifecycle API; agents can poll status and handle confirmations programmatically | MEDIUM | pending → building → signing → submitted → confirmed/failed; intentId for tracking |
| Token + program whitelist per-agent | Fine-grained policy: "this agent can only swap SOL→USDC via Jupiter, nothing else" | MEDIUM | Whitelist stored per API key or global; checked before approval prompt |
| Cooldown between transactions | Prevents agent runaway: "no more than 1 tx per 30 seconds" even within other limits | LOW | Timestamp of last approved tx; reject if within cooldown window |
| Autonomy dial: auto-approve within limits | For low-risk intents that satisfy all guardrails, skip approval prompt (user opt-in) | HIGH | Requires high user trust; opt-in only; still logs every action; conflicts with table-stakes approval requirement unless user explicitly enables |
| Hardware signer for agent-initiated txs | Agent requests signing → hardware device physically required → unique security model | MEDIUM | Routing agent intents through existing hardware signing path |
| Query endpoints without approval | Agents can read balance, tokens, price, history without user prompting — non-destructive reads are frictionless | LOW | GET /wallet, /balance, /tokens, /price, /history — no approval gate |
| curl test command generator | Developer UX: one-click copy of a working test command reduces setup friction for agent developers | LOW | Template curl with correct Authorization header and endpoint |
| Clipboard auto-clear (30s) | Security hygiene feature; not common in wallets; reduces clipboard sniffing risk | LOW | Timer after copy with toast "Clipboard will clear in 30s" |

---

### Anti-Features (Commonly Requested, Often Problematic)

These features seem reasonable but create problems that outweigh their value in this context.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Full autonomous signing (no approval) | Agents want zero-friction execution | Catastrophic if agent is compromised, buggy, or manipulated via prompt injection; removes human-in-the-loop entirely; no recovery path | Auto-approve within guardrails only; require explicit opt-in; log everything |
| Remote/cloud agent API access | Agents hosted remotely can't reach localhost | Requires auth server, public network exposure, TLS management, and infrastructure Deadbolt deliberately avoids; opens remote attack surface | Localhost-only in v1; document SSH tunnel pattern for advanced users |
| Biometric-only auth (no password fallback) | Frictionless UX | macOS Touch ID not available on all Macs; biometric can be forced; no recovery if biometric fails | Always keep password as fallback; biometric is a shortcut, not a replacement |
| Storing seed phrase in app (cloud backup) | Users fear losing paper backup | Cloud storage is a primary attack vector for wallets; Apple/Google can be compelled; screenshots vulnerable to malware | Show recovery phrase on-screen once with write-down flow; metal backup recommendation |
| API key with no name/expiry/scope | Simpler to implement | Unmanageable at scale; user can't tell which key belongs to which agent; no audit trail | Require name at creation; show last-used timestamp; add optional expiry |
| Hard lockout after wrong password | Seems secure | Permanently locked wallets with funds are a real user failure mode; support burden; rage-quit | Exponential delay after failed attempts; never permanent lockout |
| One global guardrail for all API keys | Simpler UI | Single compromised agent can exhaust shared daily limit, blocking all other agents | Per-key guardrail overrides on top of global defaults (v2 consideration) |
| Transaction history in agent API | Agents want context | Large history payloads; privacy concern; already accessible via Helius enrichment on read endpoints | Provide /history endpoint returning last N transactions; no sensitive internal data |

---

## Feature Dependencies

```
[App Password Auth]
    └──required-by──> [Vault Unlock / Lock]
    └──required-by──> [Guardrail Bypass]
    └──required-by──> [Sensitive Op Re-auth (reveal mnemonic, delete wallet)]

[Biometric Unlock]
    └──requires──> [App Password Auth] (fallback always needed)
    └──requires──> [Idle Timeout] (biometric only useful if app locks)

[Idle Timeout]
    └──requires──> [App Password Auth] (something to unlock after timeout)

[Agent API Server]
    └──requires──> [Bearer Token Auth] (no open server)
    └──required-by──> [Agent Signing Prompt]
    └──required-by──> [Query Endpoints]
    └──required-by──> [Intent Lifecycle Tracking]

[Bearer Token Auth]
    └──required-by──> [Token Management UI] (create, revoke, copy)

[Agent Signing Prompt]
    └──requires──> [Transaction Simulation] (show sim result in prompt)
    └──requires──> [Guardrails Engine] (checked before prompt shown)
    └──enhances──> [Hardware Signing] (can route through ESP32)

[Guardrails Engine]
    └──requires──> [App Password Auth] (for bypass flow)
    └──required-by──> [Manual Send Flow] (guardrails on manual tx too)
    └──required-by──> [Agent Signing Prompt]

[ESP32 BIP39 Firmware]
    └──required-by──> [Mnemonic Display Flow in App]
    └──required-by──> [Word Verification Quiz]
    └──required-by──> [Device Identity Verification]

[Mnemonic Display Flow]
    └──requires──> [ESP32 BIP39 Firmware] (mnemonic comes from device)
    └──required-by──> [Word Verification Quiz] (quiz follows display)

[Word Verification Quiz]
    └──required-by──> [Backup Confirmed State] (clears "backup not done" warning)

[Intent Lifecycle Tracking]
    └──requires──> [Agent API Server]
    └──enhances──> [Agent Signing Prompt] (prompt shows live status)
```

### Dependency Notes

- **App Password Auth requires Vault Unlock**: The vault is unlocked with the app password; they share a single credential intentionally (as decided in PROJECT.md). This simplifies UX at the cost of no separate vault-vs-app password.
- **Biometric requires Password Auth as fallback**: Touch ID on macOS is unavailable on all machines (confirmed in PROJECT.md: "Testing on macOS desktop (no Touch ID on this machine)"). Biometric is an optional shortcut.
- **Agent Signing Prompt requires Guardrails Engine**: Guardrails are evaluated before the approval prompt is shown. If guardrails block, prompt never appears — structured error goes to agent instead.
- **ESP32 BIP39 Firmware blocks backup UX**: The full mnemonic backup flow (display + quiz) cannot be built until the firmware generates and returns BIP39 mnemonics. This is the critical path for hardware wallet feature completion.
- **Transaction Simulation enhances Signing Prompt**: Simulation runs in background after intent is received. Prompt may appear before simulation completes and update in-place when result arrives (as specified in PROJECT.md).

---

## MVP Definition

This is a subsequent milestone on an existing working wallet. The MVP for this milestone is the minimal set that makes the agent API + hardware backup + auth system functional end-to-end.

### Launch With (v1 Milestone)

- [x] App password at launch and after idle timeout — safety baseline; vault is useless without a lock
- [x] Biometric as optional unlock (graceful no-op when Touch ID unavailable) — expected in 2025; low-effort add
- [x] Auto-lock with configurable timeout (1 min / 5 min / 15 min / 1 hr / 24 hr) — Phantom/Coinbase standard
- [x] Re-auth gate on: reveal mnemonic, delete wallet, create/revoke API key — sensitive op protection
- [x] ESP32 BIP39 mnemonic generation + display flow — hardware wallet has no value if no backup path
- [x] Word-by-word verification quiz (3-5 words) — standard; no backup is trusted without verification
- [x] Agent API server (axum, localhost:9876, bearer token auth) — core value delivery
- [x] Token management UI (create, revoke, copy, name) — unusable API without key management
- [x] Agent signing prompt (overlay + queue) with simulation result — human-in-the-loop is non-negotiable
- [x] Intent lifecycle tracking (pending → confirmed/failed) — agents can't function without status feedback
- [x] Query endpoints without approval (balance, tokens, price, history) — read-only is frictionless and safe
- [x] Guardrails engine: per-tx limit, daily limit, cooldown — core safety for autonomous agent
- [x] Token whitelist + program whitelist — scope restriction; "only Jupiter swaps" is a key use case
- [x] Guardrail bypass with password + timeout — user must be able to override
- [x] Specific error messages to agent on limit exceeded — agent usability baseline

### Add After Validation (v1.x)

- [ ] Auto-approve within guardrails (opt-in) — reduces friction for trusted setups; needs trust baseline first
- [ ] Per-API-key guardrail overrides — multiple agents with different limits; adds UI complexity
- [ ] Vanity address generation — nice ergonomics; not blocking any flow
- [ ] Import from Solana CLI keypair JSON — power user feature; small audience

### Future Consideration (v2+)

- [ ] Ledger/Trezor integration — out of scope (PROJECT.md); different hardware path
- [ ] Remote agent API via SSH tunnel / reverse proxy — networking complexity; out of v1 scope
- [ ] Multisig (Squads v4) — different use case; mentioned in out-of-scope
- [ ] Mobile platform (iOS/Android) — desktop-first; biometric story changes on mobile

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| App password / lock / timeout | HIGH | LOW | P1 |
| ESP32 BIP39 mnemonic generation | HIGH | HIGH | P1 |
| Word verification quiz | HIGH | LOW | P1 |
| Agent API server + bearer token | HIGH | MEDIUM | P1 |
| Token management UI | HIGH | LOW | P1 |
| Agent signing prompt + queue | HIGH | MEDIUM | P1 |
| Intent lifecycle (pending → confirmed) | HIGH | MEDIUM | P1 |
| Guardrails engine (limits + whitelist) | HIGH | MEDIUM | P1 |
| Guardrail bypass with password | HIGH | LOW | P1 |
| Specific guardrail error messages | MEDIUM | LOW | P1 |
| Transaction simulation in prompt | HIGH | MEDIUM | P1 |
| Query endpoints (no approval) | HIGH | LOW | P1 |
| Biometric unlock (optional) | MEDIUM | MEDIUM | P2 |
| Device identity verify on reconnect | MEDIUM | LOW | P2 |
| curl test command generator | MEDIUM | LOW | P2 |
| Clipboard auto-clear (30s) | LOW | LOW | P2 |
| Auto-approve within guardrails | MEDIUM | HIGH | P3 |
| Per-API-key guardrail overrides | MEDIUM | MEDIUM | P3 |
| Vanity address generation | LOW | MEDIUM | P3 |

**Priority key:**
- P1: Must have for this milestone
- P2: Should have, add within milestone if capacity allows
- P3: Future milestone

---

## Competitor Feature Analysis

These wallets inform what users will expect from analogous features.

| Feature | Phantom (Solana desktop) | Coinbase Wallet | Deadbolt Approach |
|---------|--------------------------|-----------------|-------------------|
| App lock | Settings → auto-lock; 1 min to 1 day; Face ID optional | 24h default; configurable | Configurable timeout; biometric optional; password is vault password |
| Seed backup | Shown at creation; no verification quiz | Shown at creation; quiz required | Shown from ESP32 firmware; quiz in app; backup = hardware device |
| Transaction signing | UI review with balance diff preview | UI review | UI review + agent overlay + queue; simulation result shown |
| API access | None (extension popup model) | None (consumer wallet) | Embedded localhost REST API with bearer tokens; unique differentiator |
| Spending limits | None | None | Configurable guardrails (per-tx, daily, cooldown, whitelist) |
| Hardware wallet | Ledger (via Wallet Adapter) | Ledger | ESP32 direct serial; $5 device; own firmware |

No competitor Solana wallet combines an embedded agent API with configurable guardrails and a DIY hardware signer. The combination is the differentiator.

---

## Sources

- [Phantom Wallet Auto-Lock Documentation](https://help.phantom.com/hc/en-us/articles/28951350406803-How-to-lock-your-Phantom-app) — MEDIUM confidence (verified official docs)
- [Smashing Magazine: Designing for Agentic AI UX Patterns](https://www.smashingmagazine.com/2026/02/designing-agentic-ai-practical-ux-patterns/) — HIGH confidence (current, peer-reviewed publication, 2026)
- [Helius: How to Build a Secure AI Agent on Solana](https://www.helius.dev/blog/how-to-build-a-secure-ai-agent-on-solana) — HIGH confidence (official Helius docs, current)
- [Autonomous Agents on Blockchains: Standards, Execution Models, and Trust Boundaries](https://arxiv.org/html/2601.04583v1) — HIGH confidence (academic paper, 2026)
- [Coinbase Agentic Wallets](https://www.coinbase.com/developer-platform/discover/launches/agentic-wallets) — HIGH confidence (official Coinbase developer docs)
- [Carbon Design System: Generate an API Key Pattern](https://carbondesignsystem.com/community/patterns/generate-an-api-key/) — HIGH confidence (established design system)
- [Trezor: What is BIP39](https://trezor.io/learn/a/what-is-bip39) — HIGH confidence (official hardware wallet vendor)
- [SafePal: Seed Verification UX Flow](https://safepalsupport.zendesk.com/hc/en-us/articles/4411682976155-How-to-verify-the-mnemonic-phrase-seed-phrase-on-S1-hardware-wallet) — MEDIUM confidence (hardware wallet vendor docs)
- [D'CENT Wallet: Biometric vs PIN](https://store.dcentwallet.com/blogs/post/is-biometric-authentication-safe-for-crypto-why-fingerprint-wallets-are-replacing-pins) — MEDIUM confidence (vendor blog)
- [Solana simulateTransaction RPC Method](https://solana.com/docs/rpc/http/simulatetransaction) — HIGH confidence (official Solana docs)
- [Fystack: MPC Wallets and Policy-Based Guardrails](https://fystack.io/blog/mpc-wallets-the-critical-infrastructure-for-enterprise-grade-web3-security) — MEDIUM confidence (industry blog, current)
- [Google Wallet: Re-authentication Pattern](https://support.google.com/wallet/answer/12059519?hl=en) — HIGH confidence (official Google docs)
- [Exodus Wallet: Auto-Lock Feature](https://www.exodus.com/support/en/articles/8598647-how-do-i-use-the-auto-lock-feature) — MEDIUM confidence (official support docs)

---

*Feature research for: Deadbolt — Solana wallet with agent API, ESP32 hardware signer, and transaction guardrails*
*Researched: 2026-03-16*
