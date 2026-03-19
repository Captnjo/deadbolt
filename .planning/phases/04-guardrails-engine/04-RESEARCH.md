# Phase 04: Guardrails Engine - Research

**Researched:** 2026-03-19
**Domain:** Flutter/Dart UI extension + Rust FFI bridge (FRB v2) + existing GuardrailsEngine
**Confidence:** HIGH — research based entirely on reading the actual codebase, no external sources needed

## Summary

Phase 4 is almost entirely an integration and UI phase. The Rust `GuardrailsEngine` with `check()`, `record_transaction()`, and `GuardrailsConfig` persistence already exists and is fully tested. The FRB bridge in `deadbolt_bridge/src/api/agent.rs` already imports `GuardrailsConfig`. The Flutter side needs: (1) new FRB bridge functions for reading/writing guardrail config, (2) a `GuardrailsSettingsSection` widget following the `SecuritySettingsSection` pattern, (3) guardrail checks injected into `SendNotifier.signAndSubmit()` and `SwapNotifier.signAndSubmit()` before the signing step, and (4) inline bypass UI on the review screens.

The key additions to the Rust side are: add `enabled: bool` field to `GuardrailsConfig`, add `output_mint` checking to `intent_mint()` for Swap intents, update `start_agent_server` to pass the real config (not `GuardrailsConfig::default()`), and add two new bridge functions (`get_guardrails_config`, `update_guardrails_config`). The master toggle needs to short-circuit `check()` when `enabled == false`.

**Primary recommendation:** Build the Rust additions and bridge first (one plan), then the Flutter settings section (one plan), then the send/swap enforcement + bypass (one plan). This order minimizes blocked work.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Token Whitelist UX**
- Searchable picker from held tokens (icon, name, mint) PLUS text field for pasting arbitrary mint addresses — two input methods, one list
- Empty whitelist = all tokens allowed (opt-in safety, matches current `GuardrailsEngine` behavior)
- SOL transfers are NOT subject to the token whitelist — whitelist only governs SPL tokens (matches engine: SOL intents return `None` for mint, pass check)
- Swap output tokens ARE checked — if user swaps SOL→BONK and BONK isn't whitelisted, it's blocked. Whitelist governs what tokens you can acquire, not just send
- Individual token removal via X/remove button on each row
- Each whitelisted token row shows: icon + display name + truncated mint address (using existing token metadata)
- NFT sends are NOT subject to guardrails in v1

**Bypass Flow**
- Inline warning banner on send/swap confirmation screen: specific violation message + "Override with Password" button — stays on same screen, no navigation
- Password override = bypass ALL guardrail checks for this one transaction (not per-violation). One password entry, transaction proceeds
- One-shot only — override applies to this single transaction, no timed window (consistent with Phase 1 "no grace period" decision)
- Agents CANNOT bypass guardrails. If an agent intent is blocked, it gets HTTP 403 with specific error. User must adjust guardrails settings. Agent retries after settings change

**Agent Error Messages**
- HTTP 403 with specific violation: "Token not in whitelist: EPjF...Dt1v" — agent can adapt behavior (GRDL-05)
- Already implemented in `GuardrailsEngine.check()` returning `DeadboltError::GuardrailViolation(message)` — just needs to surface through the API response

**Manual Transaction Enforcement**
- Guardrails check at confirmation step (right before signing), on the review screen — user sees full details + guardrail warning together
- Same Rust `GuardrailsEngine.check()` via FRB bridge — single source of truth for agent and manual checks
- Specific rule + values in violation message: "Token BONK (DezX...ump) is not in your whitelist" — clear, actionable

**Settings Layout**
- New "Guardrails" section in the existing Settings screen (below Security section)
- Master on/off toggle for all guardrails — when off, no checks run on any transaction (agent or manual)
- Toggling guardrails OFF requires password authentication (security-sensitive action)
- Token whitelist: expandable card titled "Token Whitelist" — shows count when collapsed, full list when expanded. "Add Token" button opens picker/text field sheet

**Program Whitelist**
- Deferred to v2. The `program_whitelist` field exists in `GuardrailsConfig` but no UI is built this phase

### Claude's Discretion
- FRB bridge function signature for guardrail checks on manual transactions
- Exact picker sheet layout and search behavior for adding tokens
- How to surface the guardrails master toggle state to the Rust engine (config field or separate flag)
- Token metadata resolution for manually-pasted mint addresses (Helius DAS lookup or display as raw address)
- Expandable card animation and collapsed count display

### Deferred Ideas (OUT OF SCOPE)
- Program whitelist UI — v2 (field exists in config, no UI this phase)
- Per-tx SOL/USD limits UI — GRDL-V2-01
- Daily transaction count and USD spend limits UI — GRDL-V2-02
- Cooldown between agent transactions — GRDL-V2-03
- SQLite persistence for daily counters — GRDL-V2-04 (currently in-memory, resets on restart)
- USD price feed integration for dollar-amount guardrails — depends on GRDL-V2-01/V2-02
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| GRDL-01 | User can configure token whitelist (allow-list of token mints agents can interact with) | `token_whitelist: Vec<String>` already in `GuardrailsConfig`; needs Flutter settings UI to read/write it via FRB bridge |
| GRDL-02 | User can configure program whitelist (allow-list of programs agents can call) | Field exists in `GuardrailsConfig.program_whitelist`; per CONTEXT.md this means the UI section header + toggle, no actual UI for adding programs — or simply skip visible program whitelist UI. Re-read CONTEXT.md: "Program whitelist UI deferred to v2." This req maps to the config field existing; the planner should note GRDL-02 is satisfied by the existing `program_whitelist` field in config (persisted) without v1 UI |
| GRDL-03 | Whitelists configurable via text field (mint address) and searchable picker from held tokens | Token picker sheet using `balanceProvider` token list; text field for arbitrary mint paste; both feed same `token_whitelist` array |
| GRDL-04 | Guardrails apply to both agent-initiated and manual transactions | Agent path: `submit_intent_handler` already calls `guardrails.check()`; manual path: inject check in `SendNotifier.signAndSubmit()` and `SwapNotifier.signAndSubmit()` before signing |
| GRDL-05 | When guardrail blocks a transaction, agent receives specific error message | `DeadboltError::GuardrailViolation(message)` → HTTP 403 already wired in `submit_intent_handler`; needs master toggle check added |
| GRDL-06 | User can bypass a guardrail block with app password (timed window) | Inline banner in `_ReviewStep` / swap review screen; calls `showAuthChallengeDialog()`; one-shot bypass flag in provider state |
| GRDL-07 | Guardrails settings UI accessible from settings screen | New `GuardrailsSettingsSection` widget in `settings_screen.dart` |
| INFR-04 | Guardrail state (whitelists) persisted to disk, survives app restart | `AppConfig.save()` with 0o600 permissions already handles this; `GuardrailsConfig` is nested in `AppConfig` with serde; needs `enabled` field added with `#[serde(default = "default_true")]` |
</phase_requirements>

---

## Standard Stack

All technology is already in place — this phase adds no new dependencies.

### Core (existing, already in use)
| Component | Version | Purpose | Location |
|-----------|---------|---------|---------|
| flutter_rust_bridge | 2.11.1 | Rust↔Flutter FFI | `lib/src/rust/api/agent.dart` (generated) |
| flutter_riverpod | current | State management | all providers |
| shared_preferences | current | Non-sensitive settings (master toggle) | `agent_provider.dart` pattern |
| deadbolt_core `GuardrailsEngine` | — | Guardrail enforcement logic | `rust/deadbolt_core/src/agent/guardrails.rs` |
| deadbolt_core `AppConfig` | — | Config persistence (0o600) | `rust/deadbolt_core/src/models/config.rs` |

### No new packages needed

All capabilities required (token metadata, auth challenge, settings UI patterns, FRB bridge) are already present in the codebase.

---

## Architecture Patterns

### Recommended File Structure (new files)

```
lib/
├── features/settings/
│   └── guardrails_settings_section.dart   # New: GuardrailsSettingsSection widget
├── providers/
│   └── guardrails_provider.dart           # New: GuardrailsNotifier (follows AgentKeyNotifier pattern)
└── (no other new files needed)

rust/deadbolt_bridge/src/api/
└── guardrails.rs                          # New: FRB bridge for guardrail config read/write + manual check
```

Files modified:
- `rust/deadbolt_core/src/models/config.rs` — add `enabled: bool` to `GuardrailsConfig`
- `rust/deadbolt_core/src/agent/guardrails.rs` — honor `enabled` flag in `check()`, fix `intent_mint()` to check `output_mint` for Swap intents
- `rust/deadbolt_bridge/src/api/agent.rs` — pass real config (not default) to `AgentServer::start()`; update live guardrails on config change
- `rust/deadbolt_bridge/src/lib.rs` (or mod.rs) — declare new `guardrails` module
- `lib/features/settings/settings_screen.dart` — add `GuardrailsSettingsSection` below `SecuritySettingsSection`
- `lib/providers/send_provider.dart` — inject guardrail check before signing in `signAndSubmit()`
- `lib/providers/swap_provider.dart` — inject guardrail check before signing in `signAndSubmit()`
- `lib/features/send/send_screen.dart` — add guardrail warning banner to `_ReviewStep`
- `lib/features/swap/swap_screen.dart` — add guardrail warning banner to review step

### Pattern 1: FRB Bridge for Guardrail Config (new `guardrails.rs`)

The bridge must: (a) read current config, (b) write updated config and persist, (c) push config update to running server, (d) perform a manual-transaction guardrail check without an `Intent` object.

```rust
// rust/deadbolt_bridge/src/api/guardrails.rs

/// Get current guardrails config as a DTO.
#[frb(sync)]
pub fn get_guardrails_config() -> GuardrailsConfigDto {
    let mgr = super::wallet::manager_pub().read().unwrap();
    let cfg = &mgr.config().guardrails;
    GuardrailsConfigDto {
        enabled: cfg.enabled,
        token_whitelist: cfg.token_whitelist.clone(),
    }
}

/// Update guardrails config. Persists to disk and pushes to live server.
pub fn update_guardrails_config(dto: GuardrailsConfigDto) -> Result<(), String> {
    // 1. Write to disk config
    {
        let mut mgr = super::wallet::manager_pub().write().map_err(|e| e.to_string())?;
        let config = mgr.config_mut();
        config.guardrails.enabled = dto.enabled;
        config.guardrails.token_whitelist = dto.token_whitelist.clone();
        config.save().map_err(|e| e.to_string())?;
    }
    // 2. Push to live server if running
    if let Ok(guard) = super::agent::agent_server().lock() {
        if let Some(server) = guard.as_ref() {
            let mut engine = server.state().guardrails.lock().unwrap();
            // Reconstruct updated config
            engine.update_config(/* reconstructed GuardrailsConfig */);
        }
    }
    Ok(())
}

/// Check a manual transaction (send/swap) against guardrails.
/// Called from Flutter review screen before signing.
/// Returns None if passes, Some(violation_message) if blocked.
#[frb(sync)]
pub fn check_manual_transaction(
    mint: Option<String>,         // None for SOL send
    output_mint: Option<String>,  // Some for swap output token
) -> Option<String> { ... }
```

**DTO for FRB:**
```rust
pub struct GuardrailsConfigDto {
    pub enabled: bool,
    pub token_whitelist: Vec<String>,
}
```

### Pattern 2: GuardrailsNotifier (follows AgentKeyNotifier)

```dart
// lib/providers/guardrails_provider.dart

class GuardrailsNotifier extends Notifier<GuardrailsConfigDto> {
  @override
  GuardrailsConfigDto build() {
    try {
      return guardrails_bridge.getGuardrailsConfig();
    } catch (_) {
      return GuardrailsConfigDto(enabled: true, tokenWhitelist: []);
    }
  }

  Future<void> setEnabled(bool enabled) async {
    await guardrails_bridge.updateGuardrailsConfig(
      GuardrailsConfigDto(
        enabled: enabled,
        tokenWhitelist: state.tokenWhitelist,
      ),
    );
    state = state.copyWith(enabled: enabled);
  }

  Future<void> addToken(String mint) async { ... }
  Future<void> removeToken(String mint) async { ... }
}

final guardrailsProvider = NotifierProvider<GuardrailsNotifier, GuardrailsConfigDto>(
  GuardrailsNotifier.new,
);
```

### Pattern 3: Inline Guardrail Warning Banner

The `_ReviewStep` in `send_screen.dart` already has a simulation warning pattern (lines 620-680). The guardrail violation banner follows the same visual weight:

```dart
// In _ReviewStep.build() — after simulation card
if (guardrailViolation != null) ...[
  const SizedBox(height: 12),
  Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: BrandColors.error.withAlpha(20),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: BrandColors.error.withAlpha(60)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.shield_outlined, color: BrandColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(guardrailViolation!,
            style: const TextStyle(color: BrandColors.error, fontSize: 13))),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: BrandColors.warning),
            onPressed: _handleBypassWithPassword,
            child: const Text('Override with Password'),
          ),
        ),
      ],
    ),
  ),
],
```

The "Confirm" button is disabled when `guardrailViolation != null && !_bypassed`.

### Pattern 4: Guardrail Check in SendNotifier

```dart
// In SendNotifier.signAndSubmit(), before the blockhash fetch:
Future<void> signAndSubmit() async {
  // 1. Check guardrails (before any signing work)
  final asset = state.asset;
  String? mint;
  if (asset is SendToken) mint = asset.tokenBalance.definition.mint;

  final violation = guardrails_bridge.checkManualTransaction(mint: mint, outputMint: null);
  if (violation != null) {
    state = state.copyWith(guardrailViolation: violation);
    return; // UI shows banner; user must bypass
  }

  // 2. Continue with existing signing flow...
}
```

The `SendState` gets a new `guardrailViolation: String?` field and `guardrailBypassed: bool` field.

### Pattern 5: GuardrailsConfig `enabled` Field

```rust
// In GuardrailsConfig struct:
#[serde(default = "default_true")]
pub enabled: bool,

fn default_true() -> bool { true }

// In GuardrailsEngine.check():
pub fn check(&self, intent: &Intent, usd_value: Option<f64>) -> Result<(), DeadboltError> {
    if !self.config.enabled {
        return Ok(()); // master toggle off — all checks skip
    }
    // ... existing check logic unchanged ...
}
```

**Backward compat:** `#[serde(default = "default_true")]` means existing config files without `enabled` field will load as `enabled: true` — safe default.

### Pattern 6: Swap Output Token Checking

The current `intent_mint()` in `guardrails.rs` checks `input_mint` for Swap intents. Per the decision, swap OUTPUT tokens must also be checked (whitelist governs what you can acquire). This requires checking the `output_mint` field of `IntentType::Swap`.

```rust
fn intent_mint(intent: &Intent) -> Option<String> {
    match &intent.intent_type {
        IntentType::SendToken { mint, .. } => Some(mint.clone()),
        // Check output_mint for swaps — this is what you're acquiring
        IntentType::Swap { output_mint, .. } => Some(output_mint.clone()),
        IntentType::Stake { lst_mint, .. } => Some(lst_mint.clone()),
        IntentType::SendSol { .. } => None,
        IntentType::SignMessage { .. } => None,
    }
}
```

Note: The existing test `test_token_whitelist` uses `token_intent` which maps to `SendToken`. A new test covering `Swap` output_mint blocking should be added.

### Pattern 7: Token Picker Sheet

The token picker reuses `balanceProvider` token list (no new API calls). Two-tab or combined sheet:

1. **Held tokens list:** `ref.watch(balanceProvider).valueOrNull?.tokenBalances` — each row shows icon (network image from token metadata), symbol, truncated mint. Filter by search query.
2. **Manual paste field:** `TextField` for raw mint address. On submit, validates base58 length (32 bytes = 44 chars), adds to whitelist. If the mint matches a known token in `balanceProvider`, show name; otherwise show raw address.

For manually pasted mints not in `balanceProvider`: display as raw truncated address without icon. Token metadata resolution via Helius DAS is left to Claude's discretion — the simplest v1 approach is raw address display for unknown mints, avoiding an async lookup.

### Anti-Patterns to Avoid

- **Passing `GuardrailsConfig::default()` to `AgentServer::start()`:** Currently `start_agent_server()` in `agent.rs` line 79 does this. After this phase, it must load the real config from `mgr.config().guardrails.clone()`. Otherwise the live server ignores user-configured whitelist.
- **Calling `update_config()` on a stale clone:** `GuardrailsEngine::update_config()` takes `&mut self` — only works if you have a mutable reference to the engine inside the `Mutex`. Acquire the lock, then call on the inner engine.
- **Using `SharedPreferences` for whitelist data:** `SharedPreferences` is for non-sensitive UI prefs (toggle state, display currency). The whitelist is in `AppConfig` (persisted to `~/.deadbolt/config.json` with 0o600). Don't split the source of truth.
- **Navigating away on guardrail block:** The decision is inline banner on the same screen. Do not push a new route or show a modal dialog.
- **Allowing agent bypass:** Agent path must not have any bypass mechanism. HTTP 403 is final for agents.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Config persistence | Custom file writer | `AppConfig.save()` | Already handles dir creation, serialization, 0o600 permissions |
| Password verification | Custom auth | `showAuthChallengeDialog()` | Proven pattern, handles loading/error states |
| Token metadata | Helius DAS API call | `balanceProvider` token list | Already fetched, no extra API calls needed for held tokens |
| Mint address validation | Custom regex | Length check (44 chars) + base58 charset | Sufficient for UX; Rust engine validates fully |
| FRB stub pattern | Modifying frb_generated.dart | New `guardrails.dart` typed stub | Established pattern: `auth.dart`, `agent.dart` — hand-written stubs with `UnimplementedError` until codegen runs |

---

## Common Pitfalls

### Pitfall 1: Live Server Config Not Updated
**What goes wrong:** User adds a token to whitelist; config.json updates; but the running `AgentServer`'s `GuardrailsEngine` still has the old config (initialized at server start).
**Why it happens:** `start_agent_server` creates a `GuardrailsEngine` with a snapshot of config; subsequent config changes don't propagate.
**How to avoid:** After `AppConfig.save()` in `update_guardrails_config()`, acquire `agent_server()` lock and call `engine.update_config(new_config)` on the inner engine.
**Warning signs:** Integration test: add token to whitelist, check it's blocked before addition and passes after.

### Pitfall 2: `GuardrailsConfig::default()` in `start_agent_server`
**What goes wrong:** `start_agent_server()` in `agent.rs` line 79 passes `GuardrailsConfig::default()` to `AgentServer::start()`. This means the server always starts with an empty whitelist regardless of what the user configured.
**Why it happens:** The default was used as a placeholder when the server was first wired up.
**How to avoid:** Load `mgr.config().guardrails.clone()` (requires read lock, drop before `.await`) and pass the real config.
**Warning signs:** User-configured whitelist has no effect on agent transactions.

### Pitfall 3: Swap Intent Checks Wrong Mint
**What goes wrong:** Current `intent_mint()` returns `input_mint` for `Swap` intents. The whitelist decision says output tokens (what you're acquiring) must be checked.
**Why it happens:** The original implementation checked which token you're spending, not which you're receiving.
**How to avoid:** Change `IntentType::Swap` branch to return `output_mint`.
**Warning signs:** Agent can swap SOL→BONK even when BONK is not whitelisted.

### Pitfall 4: `enabled` Field Default Must Be `true`
**What goes wrong:** If `enabled` defaults to `false`, existing users who upgrade will have guardrails silently disabled.
**Why it happens:** Rust `bool` defaults to `false`.
**How to avoid:** Use `#[serde(default = "default_true")]` with a `fn default_true() -> bool { true }` helper. Also set `enabled: true` in `GuardrailsConfig::default()`.
**Warning signs:** After migration test: serialize old config without `enabled` field; deserialize; verify `enabled == true`.

### Pitfall 5: Bypass State Not Reset After Transaction
**What goes wrong:** `guardrailBypassed: true` in `SendState` persists after a successful send. If user navigates back and sends another transaction, the bypass is still active.
**Why it happens:** `reset()` must include `guardrailBypassed: false`.
**How to avoid:** Ensure `SendState` and `SwapState` `reset()` clears both `guardrailViolation` and `guardrailBypassed`.
**Warning signs:** Unit test: bypass → send succeeds → reset → verify `guardrailBypassed == false`.

### Pitfall 6: Review Step vs Confirm Step Confusion
**What goes wrong:** Adding the guardrail check to `signAndSubmit()` (provider method) is correct. But `signAndSubmit` is called from the review step "Confirm" button. The violation is shown inline on the review step. Do not put the check in the confirming step (`_ConfirmingStep`) — that step is post-submit.
**Why it happens:** `SendStep.review` is where the user still has agency. `SendStep.confirming` is post-signing.
**How to avoid:** Trigger the check before calling `signAndSubmit()`, or at the start of `signAndSubmit()` before any async work. Update `SendState.guardrailViolation` so the review step can render the banner.

### Pitfall 7: Token Whitelist Check for Swap Output in Manual Flow
**What goes wrong:** The `check_manual_transaction` bridge function needs to accept both a `mint` (for send token) and an `output_mint` (for swap). The swap screen needs to pass the `outputToken.definition.mint`.
**Why it happens:** Swap state has `outputToken: TokenBalance?` which is the token being acquired.
**How to avoid:** `check_manual_transaction(mint: null, output_mint: outputToken?.definition.mint)` from swap review. The bridge function checks the non-null one against the whitelist.

---

## Code Examples

### Existing: GuardrailsEngine.check() — already correct structure
```rust
// Source: rust/deadbolt_core/src/agent/guardrails.rs:41
pub fn check(&self, intent: &Intent, usd_value: Option<f64>) -> Result<(), DeadboltError> {
    self.maybe_reset_daily_counters();
    // ... per-tx SOL, USD, daily count, cooldown checks ...
    // Token whitelist (line 110):
    if !self.config.token_whitelist.is_empty() {
        if let Some(mint) = intent_mint(intent) {
            if !self.config.token_whitelist.contains(&mint) {
                return Err(DeadboltError::GuardrailViolation(format!(
                    "Token not in whitelist: {mint}"
                )));
            }
        }
    }
    Ok(())
}
```

### Existing: AppConfig.save() — persistence pattern
```rust
// Source: rust/deadbolt_core/src/models/config.rs:128
pub fn save(&self) -> Result<(), DeadboltError> {
    let path = Self::config_path();
    // ... dir creation, serialize, write, chmod 0o600 ...
}
```

### Existing: showAuthChallengeDialog — bypass entry point
```dart
// Source: lib/features/lock/auth_challenge_dialog.dart:8
Future<bool> showAuthChallengeDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AuthChallengeDialog(),
  );
  return result ?? false;
}
```

### Existing: SecuritySettingsSection structure — follow for GuardrailsSettingsSection
```dart
// Source: lib/features/settings/security_settings_section.dart:15
class SecuritySettingsSection extends ConsumerStatefulWidget {
  const SecuritySettingsSection({super.key});
  // Column with Divider header, ListTile items, SizedBox spacing
}
```

### Existing: AgentKeyNotifier pattern — follow for GuardrailsNotifier
```dart
// Source: lib/providers/agent_provider.dart:122
class AgentKeyNotifier extends Notifier<List<agent_bridge.ApiKeyEntry>> {
  @override
  List<agent_bridge.ApiKeyEntry> build() {
    try { return agent_bridge.listApiKeys(); }
    catch (_) { return []; }
  }
  void refresh() { /* re-read from bridge */ }
}
```

### Existing: Simulation warning banner — visual pattern for guardrail banner
```dart
// Source: lib/features/send/send_screen.dart:621-641
if (sendState.simulationSuccess) ...[
  const SizedBox(height: 12),
  Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: BrandColors.success.withAlpha(20),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: BrandColors.success.withAlpha(60)),
    ),
    child: Row(children: [ Icon, Text ]),
  ),
],
```

### Existing: Inline submit_intent_handler guardrail check — agent path already works
```rust
// Source: rust/deadbolt_core/src/agent/server.rs:441
{
    let guardrails = state.guardrails.lock().unwrap();
    if let Err(e) = guardrails.check(&intent, None) {
        return (StatusCode::FORBIDDEN, Json(ErrorResponse { error: e.to_string() })).into_response();
    }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `GuardrailsConfig::default()` passed to server | Load real config from `mgr.config().guardrails` | This phase | Server enforces user-configured whitelist |
| `intent_mint()` checks `input_mint` for Swap | Check `output_mint` for Swap | This phase | Whitelist governs what tokens you can acquire |
| No `enabled` field | `enabled: bool` with `default_true` serde | This phase | Master toggle; backward compatible |
| Agent-only guardrail enforcement | Both agent and manual flows | This phase | Single source of truth via FRB bridge call |

---

## Open Questions

1. **Where to add `guardrails.rs` bridge module declaration**
   - What we know: `deadbolt_bridge/src/api/` has `agent.rs`, `wallet.rs`, `auth.rs` etc. The `lib.rs` or top-level module file must declare `pub mod guardrails;`
   - What's unclear: Whether there's a `mod.rs` or direct `lib.rs` declaration pattern
   - Recommendation: Check `rust/deadbolt_bridge/src/lib.rs` or `api/mod.rs` before writing — follow exact existing pattern. (Did not read this file; planner should verify.)

2. **Token metadata for manually pasted mints**
   - What we know: `balanceProvider` provides rich metadata for held tokens only. Arbitrary mint addresses may not be held.
   - What's unclear: v1 UX for unknown mints — display raw address or do Helius DAS lookup
   - Recommendation (Claude's discretion): Display raw truncated mint address for unknown mints. Skip Helius DAS lookup in v1 to avoid async complexity in the settings sheet. User can confirm the mint looks correct.

3. **`check_manual_transaction` needs an `Intent`-like concept without an `Intent`**
   - What we know: `GuardrailsEngine.check()` takes an `Intent`. Manual transactions don't have an `Intent` struct (no `api_token`, no `id`).
   - What's unclear: Cleanest approach — create a fake `Intent`, or add a separate `check_token_mint` method to `GuardrailsEngine`
   - Recommendation: Add `pub fn check_token_whitelist(&self, mint: &str) -> Result<(), DeadboltError>` to `GuardrailsEngine` that only checks the token whitelist and the `enabled` flag. The FRB bridge calls this directly. Avoids creating fake `Intent` objects.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (widget tests) + Rust `#[test]` (unit tests) |
| Config file | `pubspec.yaml` (flutter_test dep) / `Cargo.toml` |
| Quick run command | `flutter test test/guardrails_provider_test.dart` (Dart) / `cargo test -p deadbolt_core guardrails` (Rust) |
| Full suite command | `flutter test` / `cargo test --workspace` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GRDL-01 | Token whitelist add/remove persists | unit (Rust) | `cargo test -p deadbolt_core test_token_whitelist` | ✅ exists in guardrails.rs |
| GRDL-01 | Token whitelist UI reads/writes via bridge | unit (Dart) | `flutter test test/guardrails_provider_test.dart` | ❌ Wave 0 |
| GRDL-04 | Manual send blocked when mint not whitelisted | unit (Dart) | `flutter test test/guardrails_provider_test.dart::send_blocked` | ❌ Wave 0 |
| GRDL-05 | Agent blocked → HTTP 403 with message | unit (Rust) | `cargo test -p deadbolt_core test_token_whitelist` | ✅ (partial — needs master toggle) |
| GRDL-06 | Bypass sets bypassed flag, allows proceed | unit (Dart) | `flutter test test/guardrails_provider_test.dart::bypass` | ❌ Wave 0 |
| GRDL-07 | GuardrailsSettingsSection renders | widget (Dart) | `flutter test test/guardrails_settings_test.dart` | ❌ Wave 0 |
| INFR-04 | Config survives round-trip (enabled + whitelist) | unit (Rust) | `cargo test -p deadbolt_core test_config_roundtrip` | ✅ (needs `enabled` field added) |
| GRDL-02 | program_whitelist field persists via AppConfig | unit (Rust) | `cargo test -p deadbolt_core test_config_camel_case_serde` | ✅ existing (no UI needed) |

### Sampling Rate
- **Per task commit:** `cargo test -p deadbolt_core guardrails` (fast Rust unit tests)
- **Per wave merge:** `cargo test --workspace && flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/guardrails_provider_test.dart` — covers GRDL-01 (provider state), GRDL-04 (send blocked), GRDL-06 (bypass flag logic)
- [ ] `test/guardrails_settings_test.dart` — covers GRDL-07 (widget renders, toggle visible)
- [ ] `rust/deadbolt_core/src/agent/guardrails.rs` — add `test_enabled_toggle_skips_all_checks` and `test_swap_output_mint_blocked` to existing test module (no new file needed)
- [ ] `rust/deadbolt_core/src/models/config.rs` — add `test_guardrails_enabled_default_true` and `test_guardrails_enabled_backwards_compat` (no `enabled` field in old JSON → parses as `true`)

---

## Sources

### Primary (HIGH confidence)
All research based on direct codebase inspection:
- `rust/deadbolt_core/src/agent/guardrails.rs` — full GuardrailsEngine implementation, 7 existing tests
- `rust/deadbolt_core/src/models/config.rs` — GuardrailsConfig struct, AppConfig.save(), serde patterns
- `rust/deadbolt_core/src/agent/server.rs` — submit_intent_handler, AppState with Mutex<GuardrailsEngine>
- `rust/deadbolt_bridge/src/api/agent.rs` — bridge patterns (OnceLock singleton, manager_pub, FRB annotations)
- `lib/features/settings/security_settings_section.dart` — widget pattern to follow
- `lib/features/lock/auth_challenge_dialog.dart` — showAuthChallengeDialog() implementation
- `lib/providers/agent_provider.dart` — AgentKeyNotifier/AgentServerNotifier patterns
- `lib/providers/send_provider.dart` — signAndSubmit() injection point
- `lib/providers/swap_provider.dart` — signAndSubmit() injection point
- `lib/features/send/send_screen.dart` — _ReviewStep simulation banner pattern
- `lib/providers/balance_provider.dart` — token list source for picker

### Secondary (MEDIUM confidence)
- `.planning/phases/04-guardrails-engine/04-CONTEXT.md` — locked decisions, deferred items
- `.planning/REQUIREMENTS.md` — GRDL-01 through GRDL-07, INFR-04 definitions
- `.planning/STATE.md` — accumulated project decisions

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — read actual dependency versions and imports from code
- Architecture: HIGH — all patterns derived from existing codebase, no speculation
- Pitfalls: HIGH — pitfalls identified from actual code gaps (e.g., `GuardrailsConfig::default()` on line 79 of agent.rs confirmed by reading the file)
- Test map: MEDIUM — Dart test files don't exist yet; Rust test existence confirmed

**Research date:** 2026-03-19
**Valid until:** Stable codebase — valid until files listed in Sources are modified
