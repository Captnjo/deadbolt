---
phase: 03-agent-signing-prompt
verified: 2026-03-18T15:00:00Z
status: passed
score: 12/12 must-haves verified
re_verification:
  previous_status: gaps_found
  previous_score: 9/12
  gaps_closed:
    - "IntentNotifier drives full signing lifecycle for SignMessageIntent — sign_bridge.signMessage called, isSignMessage early-return skips sendTransaction, intent transitions to confirmed with hex signature"
    - "Transaction simulation runs in background — _runSimulation sets SimulationPhase.running, calls send_bridge.buildUnsignedSendSol/buildUnsignedSendToken, calls rpc.simulateTransaction, updates to success/failed"
    - "SignMessage intents show 'Sign' button and pressing it no longer throws UnimplementedError — bridges to real Rust signing path"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "E2E: POST send_sol intent, signing prompt auto-appears, approve, confirm lifecycle"
    expected: "201 from server, sheet auto-shows, lifecycle transitions signing->submitting->confirmed"
    why_human: "Requires running app + live server + network RPC"
  - test: "E2E: POST sign_message intent, sheet shows 'Sign' button and message preview, tapping Sign transitions to confirmed"
    expected: "Sheet shows info banner, truncated message, 'Sign' button; tapping Sign produces hex signature and transitions to confirmed without on-chain submission"
    why_human: "Runtime behavior + visual layout + sign_message end-to-end confirmation"
  - test: "E2E: SendSol simulation — prompt shows 'Simulation: Running...' then 'Simulation: Passed'"
    expected: "Simulation row visible immediately after intent POSTed; transitions to passed or failed with units consumed"
    why_human: "Real-time UI state change requires running app + live RPC"
  - test: "Queue flow: POST 3 intents, badge shows 3, each Review opens correct intent, reject advances to next"
    expected: "Badge increments, next pending slides in after reject"
    why_human: "Real-time badge updates, visual queue interaction"
  - test: "Dismiss flow: swipe down sheet, intent stays pending, badge unchanged"
    expected: "Intent remains in queue with pending lifecycle"
    why_human: "Gesture-based dismiss, state persistence"
  - test: "Idle-lock: lock app, POST intent, badge appears but sheet does not auto-show"
    expected: "Badge visible on nav rail, no bottom sheet until unlock"
    why_human: "Timing-dependent auth state behavior"
---

# Phase 3: Agent Signing Prompt Verification Report

**Phase Goal:** AI agents can POST transaction intents and users review, simulate, approve, or reject them through a non-blocking overlay
**Verified:** 2026-03-18T15:00:00Z
**Status:** passed
**Re-verification:** Yes — after gap closure (plans 03-05 and 03-06)

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Agent can POST a sign_message intent and the server parses it without error | VERIFIED | `IntentType::SignMessage { message: String }` in `rust/deadbolt_core/src/agent/intent.rs` line 26; serde roundtrip tests pass — unchanged from initial |
| 2 | Flutter can call approveIntent, rejectIntent, updateIntentStatus through FRB bridge | VERIFIED | All 3 functions in `lib/src/rust/api/agent.dart` lines 68-86 — FRB codegen re-run in plan 05 confirmed functions still present |
| 3 | Flutter can subscribe to streamIntents and receive IntentEvent objects | VERIFIED | `streamIntents()` in `agent.dart` line 64; `IntentEvent` class at line 142 — confirmed after codegen |
| 4 | PendingIntent model can parse all 5 IntentType variants from JSON | VERIFIED | `AgentIntentType.fromJson` in `lib/models/intent.dart` lines 14-47 — unchanged |
| 5 | IntentNotifier subscribes to streamIntents and adds new intents to state | VERIFIED | `_subscribeToIntents()` in `lib/providers/intent_provider.dart` lines 28-59 — unchanged |
| 6 | IntentNotifier can approve, reject, and run simulation on pending intents | VERIFIED | `approve()` and `reject()` wired; `_runSimulation` now calls `send_bridge.buildUnsignedSendSol`/`buildUnsignedSendToken` and `rpc.simulateTransaction` — gap 2 closed |
| 7 | IntentNotifier drives full signing lifecycle: signing -> submitting -> confirmed/failed | VERIFIED | Full lifecycle for SendSolIntent, SendTokenIntent; SignMessageIntent now calls `sign_bridge.signMessage` with `isSignMessage` early-return that transitions directly to confirmed — gap 1 and 3 closed |
| 8 | pendingIntentCountProvider returns count of pending intents for badge display | VERIFIED | `pendingIntentCountProvider` at line 321 counts `IntentLifecycle.pending` — unchanged |
| 9 | Root navigator key is accessible via a Provider for global bottom sheet display | VERIFIED | `rootNavigatorKeyProvider` in `lib/routing/app_router.dart` — unchanged |
| 10 | User sees a bottom sheet with full intent preview when a new intent arrives | VERIFIED | `signing_prompt_sheet.dart` — unchanged; `showSigningPrompt()` and `DraggableScrollableSheet` confirmed |
| 11 | Pending Requests section appears at top of Agent API screen with queue rows | VERIFIED | `agent_api_screen.dart` lines 399-428 — unchanged |
| 12 | Badge count appears on Agent API NavigationRail icon when pending intents exist | VERIFIED | `app_shell.dart` `pendingIntentCountProvider` watch and `Badge(` — unchanged |

**Score:** 12/12 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `rust/deadbolt_bridge/src/api/sign.rs` | sign_message function + sign_serialized_transaction | VERIFIED | `pub fn sign_message(message_hex: String) -> Result<SignedTxDto, String>` at line 15; decodes hex, calls `signer.sign(&message_bytes)`, returns `SignedTxDto { base64: String::new(), signature: hex::encode(sig_bytes) }` |
| `rust/deadbolt_core/src/solana/builder.rs` | build_unsigned_send_sol, build_unsigned_send_token, build_unsigned_legacy | VERIFIED | All three present at lines 118, 140, 177; `build_unsigned_legacy` mirrors `build_sign_legacy` without `tx.sign()` |
| `rust/deadbolt_bridge/src/api/send.rs` | build_unsigned_send_sol and build_unsigned_send_token bridge functions | VERIFIED | Lines 92 and 116; use placeholder blockhash `"11111111111111111111111111111111"` (RPC replaces via replaceRecentBlockhash=true) |
| `lib/src/rust/api/sign.dart` | FRB-generated signMessage Dart binding | VERIFIED | `Future<SignedTxDto> signMessage({required String messageHex})` at line 18 — generated by FRB codegen in plan 05 |
| `lib/src/rust/api/send.dart` | FRB-generated buildUnsignedSendSol and buildUnsignedSendToken bindings | VERIFIED | `buildUnsignedSendSol` at line 62, `buildUnsignedSendToken` at line 75 |
| `lib/providers/intent_provider.dart` | IntentNotifier with full queue + signing pipeline including simulation and sign_message | VERIFIED | `_runSimulation` calls real RPC (line 139); `_signTransaction` calls `sign_bridge.signMessage` for SignMessageIntent (line 283); `approve()` has `isSignMessage` early-return (lines 171-182) |
| `lib/routing/app_router.dart` | Exposed rootNavigatorKeyProvider | VERIFIED | Unchanged from initial |
| `lib/features/agent/signing_prompt_sheet.dart` | Bottom sheet widget with intent preview, simulation, lifecycle progress | VERIFIED | Unchanged from initial |
| `lib/features/agent/agent_api_screen.dart` | Pending Requests queue section | VERIFIED | Unchanged from initial |
| `lib/shared/app_shell.dart` | Badge on Agent API NavigationRail + global auto-show | VERIFIED | Unchanged from initial |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `rust/deadbolt_bridge/src/api/sign.rs` | `deadbolt_core::crypto::signer` | `TransactionSigner::sign` | WIRED | `signer.sign(&message_bytes)` at line 20; `manager_pub().read()` and `get_active_signer()` at lines 18-19 |
| `rust/deadbolt_bridge/src/api/send.rs` | `rust/deadbolt_core/src/solana/builder.rs` | `builder::build_unsigned_send_sol/build_unsigned_send_token` | WIRED | `builder::build_unsigned_send_sol(&params)` at line 108; `builder::build_unsigned_send_token(&params)` at line 140 |
| `lib/providers/intent_provider.dart` | `lib/src/rust/api/sign.dart` | `sign_bridge.signMessage` | WIRED | `import '../src/rust/api/sign.dart' as sign_bridge` at line 9; `sign_bridge.signMessage(messageHex: type.message)` at line 283 |
| `lib/providers/intent_provider.dart` | `lib/src/rust/api/send.dart` | `send_bridge.buildUnsignedSendSol / buildUnsignedSendToken` | WIRED | `send_bridge.buildUnsignedSendSol(toAddress: type.to, lamports: ...)` at line 123; `send_bridge.buildUnsignedSendToken(...)` at line 128 |
| `lib/providers/intent_provider.dart` | `lib/services/solana_rpc.dart` | `rpc.simulateTransaction` | WIRED | `rpc.simulateTransaction(unsignedBase64)` at line 139 — previously NOT_WIRED, now WIRED |
| `lib/providers/intent_provider.dart` | `lib/src/rust/api/agent.dart` | `agent_bridge.streamIntents/approveIntent/rejectIntent/updateIntentStatus` | WIRED | Unchanged from initial |
| `lib/features/agent/signing_prompt_sheet.dart` | `lib/providers/intent_provider.dart` | `ref.watch(intentProvider)` | WIRED | Unchanged from initial |
| `lib/shared/app_shell.dart` | `lib/providers/intent_provider.dart` | `ref.watch(pendingIntentCountProvider)` | WIRED | Unchanged from initial |
| `lib/features/agent/agent_api_screen.dart` | `lib/providers/intent_provider.dart` | `ref.watch(intentProvider)` | WIRED | Unchanged from initial |

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| AGNT-03 | 01, 04, 05 | Agent can POST intent (send_sol, send_token, swap, sign_message) | SATISFIED | All 5 `IntentType` variants parse correctly; sign_message now signs end-to-end (plan 05 closed partial) |
| AGNT-04 | 02, 03, 04 | User sees dismissable signing prompt overlay with full preview | SATISFIED | `signing_prompt_sheet.dart` — unchanged; `isDismissible: true`, 5-type preview, `_ActionButtons` with 'Sign' for SignMessageIntent |
| AGNT-05 | 02, 03, 04 | Pending intents queue when user is away; user reviews queued list on return | SATISFIED | "PENDING REQUESTS" section, `IntentNotifier` state queue, badge — unchanged |
| AGNT-06 | 02, 04, 06 | Transaction simulation runs in background; prompt updates with results | SATISFIED | `_runSimulation` sets `SimulationPhase.running`, builds unsigned tx via Rust bridge, calls `simulateTransaction`, updates to `success`/`failed` — plan 06 closed this |
| AGNT-07 | 01, 02, 04 | User can approve or reject each intent from the signing prompt | SATISFIED | `approve()` and `reject()` fully wired — unchanged |
| AGNT-08 | 02, 04, 05 | Approved intent is built, signed (software or hardware), and submitted | SATISFIED | SendSol/SendToken: blockhash → sign → sendTransaction → poll; SignMessageIntent: signMessage → skip submission → confirmed; SwapIntent deferred (documented, out of phase scope) |
| AGNT-09 | 01, 02, 04 | Agent can poll intent status (pending → building → signing → submitted → confirmed/failed/rejected) | SATISFIED | `updateIntentStatus` called at each lifecycle step; sign_message now reaches `confirmed` via the isSignMessage early-return path |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/providers/intent_provider.dart` | 279 | `throw UnimplementedError('Swap signing requires Jupiter quote — implement in swap integration')` | Warning | Approving a swap intent crashes — documented and expected, Swap out of phase 3 scope |
| `lib/features/agent/signing_prompt_sheet.dart` | 781 | `// TODO: detect hardware wallet — for now always show hot wallet variant` | Info | Signing progress always shows "Connect your ESP32" — acceptable for phase 3 |

No blocker anti-patterns remain. The `UnimplementedError` for `SignMessageIntent` (the previous blocker at line 231) is gone. Only the Swap `UnimplementedError` remains, which is a documented and intentional deferral to a future phase.

### Gap Closure Verification

**Gap 1 — sign_message signing (AGNT-08, AGNT-03): CLOSED**

- `rust/deadbolt_bridge/src/api/sign.rs`: `pub fn sign_message(message_hex: String) -> Result<SignedTxDto, String>` present at line 15. Body contains `hex::decode`, `manager_pub().read()`, `get_active_signer()`, `signer.sign(&message_bytes)`, returns `SignedTxDto { base64: String::new(), signature: hex::encode(sig_bytes) }`.
- `lib/src/rust/api/sign.dart`: FRB-generated `Future<SignedTxDto> signMessage({required String messageHex})` at line 18.
- `lib/providers/intent_provider.dart`: `import '../src/rust/api/sign.dart' as sign_bridge` at line 9; `sign_bridge.signMessage(messageHex: type.message)` at line 283; `isSignMessage` early-return in `approve()` at lines 171-182 skips `sendTransaction` and calls `updateIntentStatus(confirmed)`.
- `grep "UnimplementedError.*Message signing"` returns no matches — confirmed absent.
- Commits `5024cc9` (Rust bridge) and `1dc0742` (Dart wiring + codegen) confirmed in git history.

**Gap 2 — simulation always idle (AGNT-06): CLOSED**

- `rust/deadbolt_core/src/solana/builder.rs`: `pub fn build_unsigned_send_sol` at line 118, `pub fn build_unsigned_send_token` at line 140, `fn build_unsigned_legacy` at line 177 — all present.
- `rust/deadbolt_bridge/src/api/send.rs`: `pub fn build_unsigned_send_sol` at line 92, `pub fn build_unsigned_send_token` at line 116 — both use placeholder blockhash `"11111111111111111111111111111111"`.
- `lib/src/rust/api/send.dart`: `buildUnsignedSendSol` at line 62, `buildUnsignedSendToken` at line 75.
- `lib/providers/intent_provider.dart` `_runSimulation`: sets `SimulationPhase.running` at line 114; calls `send_bridge.buildUnsignedSendSol` at line 123; calls `rpc.simulateTransaction` at line 139; sets `SimulationPhase.success`/`failed` at lines 141/147; has `finally { rpc.dispose() }` at line 151.
- `grep "SimulationPhase.idle"` in `intent_provider.dart` returns no matches — confirmed gap behavior absent.
- Commits `b3a463b` (Rust builders) and `365058e` (Dart simulation wiring) confirmed in git history.

**Gap 3 — Sign button crashes on sign_message: CLOSED** (same root cause as gap 1; resolved by same commits)

### Human Verification Required

#### 1. E2E Send SOL flow
**Test:** POST `{"type": "send_sol", "to": "11111111111111111111111111111111", "lamports": 1500000000}` to `http://localhost:9876/intent` while app is running and unlocked.
**Expected:** 201 response; bottom sheet auto-appears with "Send SOL" heading, simulation row shows "Running..." then "Passed"; lifecycle transitions on Approve: signing -> submitting -> confirmed.
**Why human:** Requires live app + running server + RPC connectivity.

#### 2. Sign Message end-to-end
**Test:** POST `{"type": "sign_message", "message": "48656c6c6f20576f726c64"}` (hex for "Hello World").
**Expected:** Bottom sheet shows "Sign Message" heading, info banner, "Hello World" in monospace, "Sign" button; tapping Sign transitions directly to confirmed with Ed25519 signature hex, no on-chain submission.
**Why human:** Visual layout + runtime sign_message path confirmation.

#### 3. Simulation UI states
**Test:** POST a send_sol intent and immediately observe the signing prompt.
**Expected:** Simulation row visible and shows "Simulation: Running..." briefly, then transitions to "Simulation: Passed" (or "Failed" with error detail on devnet with invalid address).
**Why human:** Real-time UI state transitions require live app.

#### 4. Queue badge and multi-intent review
**Test:** POST 3 intents in quick succession. Navigate to Agent API screen.
**Expected:** Badge on NavigationRail shows "3"; PENDING REQUESTS section shows 3 rows; each Review opens correct intent sheet.
**Why human:** Real-time badge update, queue display, sheet-per-intent behavior.

#### 5. Dismiss keeps intent pending
**Test:** Auto-show sheet appears. Swipe sheet down to dismiss.
**Expected:** Sheet closes; badge and PENDING REQUESTS entry remain.
**Why human:** Gesture dismiss behavior and state persistence.

#### 6. Idle-lock blocks auto-show but badge shows
**Test:** Lock app, POST an intent.
**Expected:** Badge appears on Agent API icon; no bottom sheet auto-shows until unlock.
**Why human:** Timing-dependent auth state interaction.

---

## Re-verification Summary

The two gaps from the initial verification (score 9/12) were fully closed by plans 03-05 and 03-06:

- Plan 03-05 (commits `5024cc9`, `1dc0742`): Added `sign_message` Rust bridge function to `sign.rs`, ran FRB codegen to generate the stable `signMessage` Dart binding in `sign.dart`, replaced the `UnimplementedError` in `_signTransaction` with a real `sign_bridge.signMessage` call, and added `isSignMessage` early-return in `approve()` to skip on-chain submission for message signing.

- Plan 03-06 (commits `b3a463b`, `365058e`): Added `build_unsigned_send_sol` and `build_unsigned_send_token` to both `deadbolt_core/src/solana/builder.rs` (core logic) and `deadbolt_bridge/src/api/send.rs` (bridge wrappers), FRB codegen was already updated in plan 05, and rewrote `_runSimulation` in `intent_provider.dart` to call the real bridge functions and `rpc.simulateTransaction`.

No regressions were found. All 12 truths are now verified. All 7 requirement IDs (AGNT-03 through AGNT-09) are satisfied. The only remaining `UnimplementedError` is for `SwapIntent`, which is a documented intentional deferral to the swap integration phase.

---
_Verified: 2026-03-18T15:00:00Z_
_Verifier: Claude (gsd-verifier)_
_Re-verification: Yes — previous score 9/12, current score 12/12_
