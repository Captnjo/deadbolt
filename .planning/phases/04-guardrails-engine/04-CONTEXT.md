# Phase 4: Guardrails Engine - Context

**Gathered:** 2026-03-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Harden the existing Rust guardrails with token whitelist UI, manual transaction enforcement, password bypass flow, and Flutter settings UI. The Rust `GuardrailsEngine` already exists with `check()`, `record_transaction()`, token whitelist logic, and `GuardrailsConfig` persisted in `~/.deadbolt/config.json`. This phase adds the Flutter UI for managing whitelists, wires guardrail checks into manual send/swap flows (not just agent intents), adds password-based bypass for blocked transactions, and creates the guardrails settings section.

**v1 scope (GRDL-01 through GRDL-07, INFR-04):** Token whitelist, guardrails settings UI, enforcement on both agent and manual transactions, specific error messages, password bypass, config persistence.

**Deferred to v2:** Per-tx SOL/USD limits (GRDL-V2-01), daily limits (GRDL-V2-02), cooldowns (GRDL-V2-03), SQLite for daily counters (GRDL-V2-04). The Rust `GuardrailsConfig` fields for these already exist but the UI and enforcement are v2.

**Program whitelist UI deferred to v2.** The `program_whitelist` field exists in `GuardrailsConfig` but no UI will be built in this phase.

</domain>

<decisions>
## Implementation Decisions

### Token Whitelist UX
- Searchable picker from held tokens (icon, name, mint) PLUS text field for pasting arbitrary mint addresses — two input methods, one list
- Empty whitelist = all tokens allowed (opt-in safety, matches current `GuardrailsEngine` behavior)
- SOL transfers are NOT subject to the token whitelist — whitelist only governs SPL tokens (matches engine: SOL intents return `None` for mint, pass check)
- Swap output tokens ARE checked — if user swaps SOL→BONK and BONK isn't whitelisted, it's blocked. Whitelist governs what tokens you can acquire, not just send
- Individual token removal via X/remove button on each row
- Each whitelisted token row shows: icon + display name + truncated mint address (using existing token metadata)
- NFT sends are NOT subject to guardrails in v1

### Bypass Flow
- Inline warning banner on send/swap confirmation screen: specific violation message + "Override with Password" button — stays on same screen, no navigation
- Password override = bypass ALL guardrail checks for this one transaction (not per-violation). One password entry, transaction proceeds
- One-shot only — override applies to this single transaction, no timed window (consistent with Phase 1 "no grace period" decision)
- Agents CANNOT bypass guardrails. If an agent intent is blocked, it gets HTTP 403 with specific error. User must adjust guardrails settings. Agent retries after settings change

### Agent Error Messages
- HTTP 403 with specific violation: "Token not in whitelist: EPjF...Dt1v" — agent can adapt behavior (GRDL-05)
- Already implemented in `GuardrailsEngine.check()` returning `DeadboltError::GuardrailViolation(message)` — just needs to surface through the API response

### Manual Transaction Enforcement
- Guardrails check at confirmation step (right before signing), on the review screen — user sees full details + guardrail warning together
- Same Rust `GuardrailsEngine.check()` via FRB bridge — single source of truth for agent and manual checks
- Specific rule + values in violation message: "Token BONK (DezX...ump) is not in your whitelist" — clear, actionable

### Settings Layout
- New "Guardrails" section in the existing Settings screen (below Security section)
- Master on/off toggle for all guardrails — when off, no checks run on any transaction (agent or manual)
- Toggling guardrails OFF requires password authentication (security-sensitive action)
- Token whitelist: expandable card titled "Token Whitelist" — shows count when collapsed, full list when expanded. "Add Token" button opens picker/text field sheet

### Program Whitelist
- **Deferred to v2.** The `program_whitelist` field exists in `GuardrailsConfig` but no UI is built this phase

### Claude's Discretion
- FRB bridge function signature for guardrail checks on manual transactions
- Exact picker sheet layout and search behavior for adding tokens
- How to surface the guardrails master toggle state to the Rust engine (config field or separate flag)
- Token metadata resolution for manually-pasted mint addresses (Helius DAS lookup or display as raw address)
- Expandable card animation and collapsed count display

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Rust Guardrails Engine (existing — to be extended)
- `rust/deadbolt_core/src/agent/guardrails.rs` — GuardrailsEngine with check(), record_transaction(), token whitelist enforcement, daily counter reset. Has tests for all check types
- `rust/deadbolt_core/src/models/config.rs` — GuardrailsConfig struct (max_sol_per_tx, max_usd_per_tx, max_daily_tx_count, max_daily_usd_total, cooldown_seconds, token_whitelist, program_whitelist). Persisted in AppConfig via serde camelCase to ~/.deadbolt/config.json
- `rust/deadbolt_core/src/agent/server.rs` — submit_intent_handler already calls guardrails.check(&intent, None) at line ~440. Returns 403 with ErrorResponse on violation

### FRB Bridge (patterns to extend)
- `rust/deadbolt_bridge/src/api/agent.rs` — Existing bridge for start/stop server, API key CRUD, update_wallet_data. Guardrails config update needs new bridge function
- `rust/deadbolt_bridge/src/api/wallet.rs` — OnceLock<RwLock<>> singleton pattern for bridge state
- `lib/src/rust/api/agent.dart` — Typed stub for FRB agent functions

### Flutter Integration Points
- `lib/features/settings/settings_screen.dart` — Settings screen (add Guardrails section)
- `lib/features/settings/security_settings_section.dart` — SecuritySettingsSection pattern to follow for GuardrailsSettingsSection
- `lib/features/lock/auth_challenge_dialog.dart` — showAuthChallengeDialog pattern for password override and toggle auth
- `lib/providers/send_provider.dart` — Send flow (add guardrail check at confirmation step)
- `lib/providers/swap_provider.dart` — Swap flow (add guardrail check at confirmation step)
- `lib/services/solana_rpc.dart` — Token metadata for whitelist picker display

### Auth System (Phase 1 decisions that apply)
- Password required to bypass guardrail blocks (AUTH-05) — no grace period
- showAuthChallengeDialog helper pattern for inline password prompts

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `GuardrailsEngine` in guardrails.rs: Full check/record pipeline with 7 tests — extend with master toggle, add program whitelist check (v2), add swap output token extraction
- `GuardrailsConfig` in config.rs: Already serializable, persisted via AppConfig.save() — add `enabled: bool` field for master toggle
- `showAuthChallengeDialog()`: Proven password prompt pattern — reuse for override and toggle auth
- `SecuritySettingsSection`: Widget pattern for settings section — follow for GuardrailsSettingsSection
- Token metadata: Existing Helius/Jupiter integration provides token icons, names, and metadata for the whitelist picker

### Established Patterns
- Riverpod Notifier for state management (follow AgentKeyNotifier pattern for guardrails state)
- FRB async functions with typed stubs before codegen
- SharedPreferences for non-sensitive settings (master toggle state)
- AppConfig.save() with 0o600 permissions for sensitive config (whitelist changes)
- ConsumerStatefulWidget for settings sections with local state

### Integration Points
- `settings_screen.dart`: Add GuardrailsSettingsSection below SecuritySettingsSection
- `send_provider.dart`: Add guardrail check before signing in send flow
- `swap_provider.dart`: Add guardrail check before signing in swap flow
- `agent.rs` bridge: Add functions for guardrail config read/write and manual tx check
- `server.rs`: Guardrail check already wired — may need to update with master toggle check

</code_context>

<specifics>
## Specific Ideas

- Inline warning on confirmation screen should feel integrated, not like a popup — same visual weight as simulation warnings in the signing prompt
- Token picker should reuse the same token data the dashboard already has — no extra API calls
- Master toggle OFF state should be visually obvious in settings (red indicator or similar) since it disables all protection
- Agent error messages should be descriptive enough that a well-built agent can auto-adapt (e.g., retry with a whitelisted token)

</specifics>

<deferred>
## Deferred Ideas

- Program whitelist UI — v2 (field exists in config, no UI this phase)
- Per-tx SOL/USD limits UI — GRDL-V2-01
- Daily transaction count and USD spend limits UI — GRDL-V2-02
- Cooldown between agent transactions — GRDL-V2-03
- SQLite persistence for daily counters — GRDL-V2-04 (currently in-memory, resets on restart)
- USD price feed integration for dollar-amount guardrails — depends on GRDL-V2-01/V2-02

</deferred>

---

*Phase: 04-guardrails-engine*
*Context gathered: 2026-03-19*
