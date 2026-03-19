---
phase: 04-guardrails-engine
verified: 2026-03-19T08:00:00Z
status: human_needed
score: 22/22 automated must-haves verified
human_verification:
  - test: "Swap enforcement visual path"
    expected: "Swap with non-whitelisted output token shows violation banner, disables Confirm"
    why_human: "Swap enforcement code is wired but was skipped during 04-04 human checkpoint due to devnet liquidity — code review confirms wiring, but runtime behavior unconfirmed"
  - test: "GRDL-02 scoping acknowledgement"
    expected: "Confirm program_whitelist field present in config.json, no UI expected in v1 (deferred per CONTEXT.md)"
    why_human: "Requirement is marked complete in REQUIREMENTS.md; v1 scope is field-only (no UI) per locked decision"
---

# Phase 04: Guardrails Engine Verification Report

**Phase Goal:** Configurable transaction guardrails enforce user-defined limits on all transactions — agent and manual — with bypass requiring the app password
**Verified:** 2026-03-19T08:00:00Z
**Status:** human_needed (all automated checks pass; 2 items require human confirmation)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | GuardrailsEngine.check() skips all checks when config.enabled == false | VERIFIED | `guardrails.rs:59-61` — master toggle early return confirmed; `test_enabled_toggle_skips_all_checks` passes |
| 2 | Swap intents check output_mint (not input_mint) against token whitelist | VERIFIED | `guardrails.rs:183` — `IntentType::Swap { output_mint, .. } => Some(output_mint.clone())`; `test_swap_output_mint_blocked` passes |
| 3 | Existing config.json without 'enabled' field deserializes as enabled: true | VERIFIED | `config.rs:61-62` — `#[serde(default = "default_true")]`; `test_guardrails_enabled_backwards_compat` passes |
| 4 | FRB bridge can read and write guardrails config | VERIFIED | `lib/src/rust/api/guardrails.dart` is FRB-generated (not a stub); `getGuardrailsConfig` and `updateGuardrailsConfig` call live RustLib bindings |
| 5 | FRB bridge can check a manual transaction mint against the token whitelist | VERIFIED | `guardrails.dart:24-28` — `checkManualTransaction` is FRB-generated, live binding |
| 6 | start_agent_server loads real GuardrailsConfig from AppConfig (not GuardrailsConfig::default()) | VERIFIED | `agent.rs:71` — `mgr.config().guardrails.clone()` confirmed; commit 8ae4bcc |
| 7 | Updating guardrails config pushes changes to the live running server | VERIFIED | `bridge/guardrails.rs:35-44` — two-phase update: disk persist then `engine.update_config(full_config)` |
| 8 | Agent path has no bypass mechanism | VERIFIED | `guardrails.rs:58` — `check(&self, intent: &Intent, usd_value: Option<f64>)` — no bypass param; `test_agent_cannot_bypass_guardrails` passes |
| 9 | GuardrailsSettingsSection appears in Settings screen below SecuritySettingsSection | VERIFIED | `settings_screen.dart:123` — `const GuardrailsSettingsSection()` after `const SecuritySettingsSection()` |
| 10 | Master toggle toggles guardrails enabled/disabled via bridge | VERIFIED | `guardrails_provider.dart:19-26` — `setEnabled` calls `guardrails_bridge.updateGuardrailsConfig` |
| 11 | Toggling guardrails OFF requires password authentication | VERIFIED | `guardrails_settings_section.dart:63-67` — `showAuthChallengeDialog(context)` before `setEnabled(false)` |
| 12 | Token whitelist card shows count when collapsed, full list when expanded | VERIFIED | `guardrails_settings_section.dart:89-107` — collapsed subtitle shows `${config.tokenWhitelist.length} tokens`; `AnimatedCrossFade` for expand |
| 13 | User can add tokens via picker from held tokens or by pasting mint address | VERIFIED | `guardrails_settings_section.dart:321-405` — search field + `Or paste a mint address` paste field both present |
| 14 | User can remove tokens via X button on each row | VERIFIED | `guardrails_settings_section.dart:172-177` — `IconButton` with `tooltip: 'Remove token'` calls `removeToken(mint)` |
| 15 | Empty whitelist shows 'No restrictions' caption | VERIFIED | `guardrails_settings_section.dart:91` — `'No restrictions \u2014 all SPL tokens allowed'` |
| 16 | Master toggle OFF shows 'All guardrails disabled' subtitle in error color | VERIFIED | `guardrails_settings_section.dart:55-58` — subtitle with `BrandColors.error` color |
| 17 | Manual send transactions are checked against guardrails before signing | VERIFIED | `send_provider.dart:141-156` — `if (!state.guardrailBypassed)` guard + `checkManualTransaction` call in `signAndSubmit` |
| 18 | Manual swap transactions check the output token mint | VERIFIED | `swap_provider.dart:242-248` — `outputMint: output?.definition.mint` passed to `checkManualTransaction` |
| 19 | When guardrail blocks a manual transaction, review screen shows inline error banner | VERIFIED | `send_screen.dart:708-748`, `swap_screen.dart:558-595` — `Icons.shield_outlined` banner with violation message |
| 20 | Confirm button disabled when guardrail violation is present and not bypassed | VERIFIED | `send_screen.dart:769`, `swap_screen.dart:618` — `guardrailViolation != null && !guardrailBypassed` disabling condition |
| 21 | User can override block with password via inline Override button | VERIFIED | `send_screen.dart:738-741`, `swap_screen.dart:588-591` — `showAuthChallengeDialog` + `bypassGuardrails()` on success |
| 22 | guardrailBypassed resets on SendState/SwapState reset (one-shot) | VERIFIED | `send.dart:51`, `swap.dart:106` — `guardrailBypassed = false` in const default constructors; reset() uses `const SendState()` |

**Score:** 22/22 automated truths verified

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `rust/deadbolt_core/src/models/config.rs` | GuardrailsConfig with enabled: bool | VERIFIED | `pub enabled: bool` at line 62 with `#[serde(default = "default_true")]` and `fn default_true() -> bool { true }` |
| `rust/deadbolt_core/src/agent/guardrails.rs` | Master toggle, swap output_mint fix, check_token_whitelist | VERIFIED | All three present; 17 tests pass including 6 new phase-04 tests |
| `rust/deadbolt_bridge/src/api/guardrails.rs` | FRB bridge for guardrails config read/write and manual tx check | VERIFIED | `get_guardrails_config`, `update_guardrails_config`, `check_manual_transaction` all present |
| `rust/deadbolt_bridge/src/api/agent.rs` | Fixed start_agent_server loading real config | VERIFIED | `mgr.config().guardrails.clone()` at line 71; `pub(crate) fn agent_server()` at line 19 |
| `rust/deadbolt_bridge/src/api/mod.rs` | pub mod guardrails | VERIFIED | Line 3: `pub mod guardrails;` |
| `lib/src/rust/api/guardrails.dart` | Typed bridge for guardrails functions | VERIFIED | FRB-generated file (not a stub) — `@generated by flutter_rust_bridge 2.11.1`; live bindings |
| `lib/providers/guardrails_provider.dart` | GuardrailsNotifier with addToken/removeToken/setEnabled | VERIFIED | All 4 methods present; `guardrailsProvider` exported |
| `lib/features/settings/guardrails_settings_section.dart` | Complete settings section UI | VERIFIED | ConsumerStatefulWidget with master toggle, expandable token whitelist, add sheet, remove button |
| `lib/features/settings/settings_screen.dart` | GuardrailsSettingsSection integrated | VERIFIED | Import at line 13, widget at line 123 |
| `lib/models/send.dart` | SendState with guardrailViolation and guardrailBypassed | VERIFIED | Both fields at lines 35-36, in constructor and copyWith |
| `lib/models/swap.dart` | SwapState with guardrailViolation and guardrailBypassed | VERIFIED | Both fields at lines 86-87, in constructor and copyWith |
| `lib/providers/send_provider.dart` | checkGuardrails + checkManualTransaction in signAndSubmit | VERIFIED | `checkManualTransaction` at line 80 and 149; `checkGuardrails` at 72; `bypassGuardrails` at 91 |
| `lib/providers/swap_provider.dart` | checkGuardrails + checkManualTransaction in signAndSubmit | VERIFIED | `checkManualTransaction` at line 127 and 244; `checkGuardrails` at 124; `bypassGuardrails` at 138 |
| `lib/features/send/send_screen.dart` | Inline guardrail violation banner in _ReviewStep | VERIFIED | `Icons.shield_outlined` at line 722; banner at lines 708-748 |
| `lib/features/swap/swap_screen.dart` | Inline guardrail violation banner in swap review step | VERIFIED | `Icons.shield_outlined` at line 572; banner at lines 558-595 |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `bridge/guardrails.rs` | `models/config.rs` | `mgr.config().guardrails` | WIRED | `bridge/guardrails.rs:15` and `bridge/guardrails.rs:41` |
| `bridge/guardrails.rs` | `agent/guardrails.rs` | `check_token_whitelist` | WIRED | `bridge/guardrails.rs:74,81` |
| `bridge/api/agent.rs` | `models/config.rs` | `mgr.config().guardrails.clone()` | WIRED | `agent.rs:71` confirmed |
| `lib/providers/guardrails_provider.dart` | `lib/src/rust/api/guardrails.dart` | `guardrails_bridge.` calls | WIRED | 8 call sites in provider |
| `guardrails_settings_section.dart` | `guardrails_provider.dart` | `ref.watch(guardrailsProvider)` | WIRED | Line 32 confirmed |
| `settings_screen.dart` | `guardrails_settings_section.dart` | import + embed widget | WIRED | Import line 13, usage line 123 |
| `send_provider.dart` | `lib/src/rust/api/guardrails.dart` | `guardrails_bridge.checkManualTransaction` | WIRED | Lines 80 and 149 |
| `send_screen.dart` | `send_provider.dart` | `sendState.guardrailViolation` | WIRED | Line 708 |
| `send_screen.dart` | `auth_challenge_dialog.dart` | `showAuthChallengeDialog` | WIRED | Line 738 |
| `swap_provider.dart` | `lib/src/rust/api/guardrails.dart` | `guardrails_bridge.checkManualTransaction` | WIRED | Lines 127 and 244 |
| `swap_screen.dart` | `swap_provider.dart` | `swapState.guardrailViolation` | WIRED | Line 558 |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| GRDL-01 | 04-01, 04-02 | Token whitelist (allow-list of mints agents can interact with) | SATISFIED | Config field + FRB bridge + settings UI all verified |
| GRDL-02 | 04-01 | Program whitelist (allow-list of programs agents can call) | SATISFIED (field only, UI v2) | `program_whitelist: Vec<String>` in config.rs; CONTEXT.md explicitly defers UI to v2; field persists via AppConfig.save() |
| GRDL-03 | 04-02 | Whitelists configurable via text field and searchable picker | SATISFIED | `guardrails_settings_section.dart` has search field + paste-mint field; Jupiter token list integrated |
| GRDL-04 | 04-01, 04-03 | Guardrails apply to both agent and manual transactions | SATISFIED | Agent: `server.rs` calls `guardrails.check()` on every intent; Manual: `send_provider.dart` and `swap_provider.dart` call `checkManualTransaction` before signing |
| GRDL-05 | 04-01 | Agent receives specific error message when blocked | SATISFIED | `GuardrailsEngine.check()` returns `DeadboltError::GuardrailViolation(format!("Token not in whitelist: {mint}"))` — HTTP 403 via existing `submit_intent_handler` (pre-existing from Phase 3) |
| GRDL-06 | 04-03 | User can bypass guardrail block with app password | SATISFIED | `showAuthChallengeDialog` + `bypassGuardrails()` in both send and swap review screens; one-shot per transaction |
| GRDL-07 | 04-02 | Guardrails settings UI accessible from settings screen | SATISFIED | `GuardrailsSettingsSection` in `settings_screen.dart` at line 123 |
| INFR-04 | 04-01 | Guardrail state persisted to disk, survives app restart | SATISFIED | `update_guardrails_config` calls `config.save()` via `AppConfig.save()` which writes to `~/.deadbolt/config.json` |

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/src/rust/api/guardrails.dart` | 1-2 | FRB-generated file (not hand-written stub) | Info | Positive: codegen ran, live bindings. Plan specified stubs-until-codegen; codegen already ran |
| `guardrails_settings_section.dart` | 315 | "Add Tokens to Whitelist" vs plan spec "Add Token to Whitelist" | Info | Plural is defensible (multi-select sheet); no functional impact |
| `guardrails_settings_section.dart` | 242 | `'Invalid mint address'` vs plan spec `'Invalid mint address (must be 44 characters)'` | Warning | Truncated message is less informative; validation range is 32-44 chars (plan specified exact 44); does not block GRDL-03 satisfaction |
| `guardrails_settings_section.dart` | 240 | Validation accepts 32-44 char mints vs plan spec 44-char only | Warning | Solana mint addresses are 32-44 base58 chars; broadened range is technically more correct but deviates from plan spec |

No blockers found.

---

## Human Verification Required

### 1. Swap enforcement runtime confirmation

**Test:** Configure token whitelist with USDC only. In the swap screen, attempt a swap where the output token is NOT USDC (e.g., SOL to BONK). Proceed to the review step.
**Expected:** Violation banner appears (`Icons.shield_outlined`, "Token not in whitelist: ..."), Confirm button is disabled, "Override with Password" button is present.
**Why human:** Swap tests were skipped during 04-04 checkpoint (steps 33-36) due to Jupiter devnet having no liquidity for custom SPL tokens. The enforcement wiring is fully confirmed by code review but the runtime path has not been exercised.

### 2. GRDL-02 scope acknowledgement

**Test:** Check `~/.deadbolt/config.json` after configuring guardrails. Verify `programWhitelist` field exists (empty array).
**Expected:** Field `"programWhitelist": []` present in guardrails object. No program whitelist UI in settings (deferred to v2 per CONTEXT.md).
**Why human:** GRDL-02 is marked [x] complete in REQUIREMENTS.md. The completion is scoped to field existence only (per locked decision in CONTEXT.md line 15: "Program whitelist UI deferred to v2"). Human confirmation that this scoping is intentional and accepted.

---

## Notable Observations

**FRB codegen ran:** The `lib/src/rust/api/guardrails.dart` file is FRB-generated (`@generated by flutter_rust_bridge 2.11.1`), not the hand-written stub the plan expected. This means the bridge bindings are live — guardrails enforcement will actually fire when the app runs, not throw `UnimplementedError`. This is strictly better than the plan anticipated.

**GuardrailsConfigDto has no copyWith in generated file:** The FRB-generated `GuardrailsConfigDto` does not have a `copyWith` method (the plan specified it). The `GuardrailsNotifier` provider compensates by constructing new DTO instances directly in each method. Functional behavior is identical.

**GRDL-02 interpretation:** The program whitelist requirement is marked complete in REQUIREMENTS.md but the UI is explicitly deferred to v2 in CONTEXT.md. The v1 completion is the field in config + persistence. This is consistent with the locked decision and the human verification in 04-04-SUMMARY.

**All 17 Rust tests pass:** Including all 6 new Phase 04 tests (`test_enabled_toggle_skips_all_checks`, `test_swap_output_mint_blocked`, `test_check_token_whitelist_method`, `test_check_token_whitelist_empty_allows_all`, `test_check_token_whitelist_disabled_allows_all`, `test_agent_cannot_bypass_guardrails`) and all 3 new config tests.

---

_Verified: 2026-03-19T08:00:00Z_
_Verifier: Claude (gsd-verifier)_
