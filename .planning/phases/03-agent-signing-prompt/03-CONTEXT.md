# Phase 3: Agent Signing Prompt - Context

**Gathered:** 2026-03-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the agent intent posting flow, dismissable signing prompt overlay, intent queue, background simulation, and full lifecycle tracking. The Rust agent server already has POST /intent and GET /intent/{id}/status routes, Intent/IntentType/IntentStatus types, approve_intent/reject_intent methods, and an `intent_sender` mpsc channel. This phase wires intents through FRB to Flutter, builds the bottom-sheet signing prompt UI, adds a pending queue section to the Agent API screen, and implements the sign-and-submit pipeline for approved intents.

**Requirements covered:** AGNT-03, AGNT-04, AGNT-05, AGNT-06, AGNT-07, AGNT-08, AGNT-09

</domain>

<decisions>
## Implementation Decisions

### Signing Prompt Overlay
- Bottom sheet that slides up from the bottom, covering ~60% of the screen
- Non-blocking — user can dismiss (swipe down or tap outside) and continue using the app
- Auto-shows when a new intent arrives while user is actively using the app
- Dismiss = "I'll deal with this later" — intent stays pending in the queue
- If multiple intents arrive in quick succession: show the first, queue the rest with a "N more pending" indicator on the sheet
- After acting on one intent, next pending intent slides in automatically

### Intent Queue
- "Pending Requests" section at the top of the existing Agent API screen
- Badge count on the Agent API sidebar icon showing pending intent count
- Each queue row: "Type + amount + time ago" one-liner (e.g., "Send 1.5 SOL - 2 min ago") with [Review] button that opens the bottom sheet
- Queue shows pending intents only — once approved/rejected, they disappear from queue (visible in normal transaction history)
- No intent expiration — intents stay pending indefinitely until the user acts
- Individual review only — no bulk reject, each intent reviewed separately
- After unlock from idle lock: badge count on sidebar, no auto-popup. User navigates to Agent API screen when ready

### Transaction Preview Content (Bottom Sheet)
- Rich preview with: agent label ("Claude agent"), intent type header, amount with USD value, recipient address (truncated middle), simulation status/result, network fee estimate
- **Send SOL/Token:** Amount, recipient, fee, simulation status
- **Swap:** Input amount and token, expected output amount and token, exchange rate, slippage %, fee, simulation status
- **Sign Message:** Raw message as UTF-8 (hex fallback if not valid UTF-8), info banner: "Message signature only. No transaction, no fees." Approve button labeled "Sign" instead of "Approve"
- Simulation runs in background; "Simulation: Running..." with spinner updates in-place when result arrives
- Approve button is enabled immediately — user can approve before simulation completes
- Simulation failure: red warning banner with error message + "Approving a failed simulation may result in a lost tx fee" — approve still available, user makes the call

### Approval & Signing Flow
- No app password required for approve — consistent with Phase 1 decision (password not required for tx signing; the review + tap is the authorization)
- After approve: bottom sheet transitions to progress view showing lifecycle: Signing... → Submitting... → Confirmed (with signature)
- Hardware wallet signing: same flow as manual send — "Connect your ESP32 to sign" with device detection if active wallet is hardware type
- On confirmation: auto-dismiss after 3 seconds, then next pending intent slides in if queue is not empty
- On signing/submission failure: show error in sheet with [Retry] and [Dismiss] buttons. Intent marked "failed". Agent sees error via status polling
- Rejection: instant, no reason field. Intent immediately gets "rejected" status. Agent sees generic rejection via polling

### Claude's Discretion
- Exact bottom sheet animation and drag handle styling
- StreamSink event format for intent notifications from Rust to Dart
- FRB bridge function signatures for intent approval/rejection/status updates
- How to fetch swap quotes/rates for the preview (can reuse existing Jupiter/DFlow integration)
- Intent Dart model structure (mirroring Rust types)
- Badge widget implementation on NavigationRail
- Progress indicator styling during signing lifecycle
- Whether to poll for confirmation or use WebSocket/stream

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Rust Agent Server (intent handling already implemented)
- `rust/deadbolt_core/src/agent/intent.rs` — Intent struct (id, intent_type, status, api_token, signature, error, created_at), IntentType enum (SendSol, SendToken, Swap, Stake), IntentStatus lifecycle (Pending → Approved → Signing → Submitted → Confirmed, or → Rejected/Failed)
- `rust/deadbolt_core/src/agent/server.rs` — AgentServer with POST /intent handler (submit_intent_handler), GET /intent/{id}/status, approve_intent/reject_intent/update_intent_status methods, `intent_sender: mpsc::UnboundedSender<Intent>` channel, AppState with intents HashMap
- `rust/deadbolt_core/src/agent/auth.rs` — Bearer token middleware, constant_time_eq validation
- `rust/deadbolt_core/src/agent/guardrails.rs` — GuardrailsEngine for pre-approval checks

### FRB Bridge (existing patterns to extend)
- `rust/deadbolt_bridge/src/api/agent.rs` — Existing bridge: start/stop server, API key CRUD, update_wallet_data. Note: `_intent_rx` was dropped in Phase 2 — Phase 3 must wire intent notifications to Flutter via StreamSink
- `rust/deadbolt_bridge/src/api/wallet.rs` — OnceLock<RwLock<>> singleton pattern for bridge state
- `lib/src/rust/api/agent.dart` — Typed stub for FRB agent functions (UnimplementedError pattern)

### Flutter Signing Flows (patterns to reuse)
- `lib/providers/send_provider.dart` — SendState/TxStatus model, simulate() and signAndSubmit() pipeline, hardware vs software signing paths, RPC confirmation polling
- `lib/providers/swap_provider.dart` — Swap quote fetching, unsigned TX signing, similar lifecycle
- `lib/services/solana_rpc.dart` — simulateTransaction(txBase64) → SimulationResult { success, unitsConsumed, err }
- `lib/features/lock/auth_challenge_dialog.dart` — showAuthChallengeDialog pattern (NOT needed for approve, but reference for dialog patterns)

### Flutter Agent Screen (integration point)
- `lib/features/agent/agent_api_screen.dart` — Existing Agent API dashboard (server toggle, keys, curl test) — pending queue section goes at top
- `lib/providers/agent_provider.dart` — AgentServerNotifier, AgentKeyNotifier, AgentServerState
- `lib/shared/app_shell.dart` — NavigationRail with 5 destinations (badge count goes on Agent API icon)
- `lib/routing/app_router.dart` — GoRouter routes (bottom sheet may need overlay route or global key approach)

### Existing Models
- `lib/models/send.dart` — SendState model (reference for intent state structure)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AgentServer.approve_intent(id)` / `reject_intent(id)` / `update_intent_status()`: Already implemented in Rust — just need FRB bridge exposure
- `intent_sender` mpsc channel: Created during server start — needs StreamSink bridge to notify Flutter of new intents
- `simulateTransaction()` in SolanaRpcClient: Proven simulation mechanism — reuse for agent intent simulation
- `_buildSignedTxSoftware()` / `_buildSignedTxHardware()` in SendProvider: Signing pipeline for both wallet types
- `showAuthChallengeDialog()`: Dialog pattern reference (though not needed for approval)
- `TxStatus` enum: State machine pattern for transaction lifecycle tracking
- `AgentApiScreen`: Already has server toggle, keys, curl test — add pending queue section at top

### Established Patterns
- Riverpod AsyncNotifier for server state management
- GoRouter for navigation with redirect guards
- SharedPreferences for non-sensitive settings
- FRB async functions with typed stubs (UnimplementedError) before codegen
- ConsumerStatefulWidget for screens with local state
- Bottom sheet via `showModalBottomSheet` (Flutter standard)

### Integration Points
- `app_shell.dart` NavigationRail: Add badge count widget to Agent API destination
- `agent_provider.dart`: Add IntentNotifier for pending intent state
- `agent.rs` FRB bridge: Add functions for intent stream, approve, reject, sign-and-submit
- `agent_api_screen.dart`: Add Pending Requests section above server toggle
- Global overlay: May need Overlay/OverlayEntry or Navigator key for showing bottom sheet from anywhere (not just Agent API screen)

</code_context>

<specifics>
## Specific Ideas

- Bottom sheet should feel like Phantom wallet's transaction approval prompt — clean, informative, non-blocking
- "N more pending" indicator keeps user aware without overwhelming them with stacked sheets
- Auto-dismiss after 3s on confirmation mirrors Phantom's behavior — quick feedback, then move on
- The rich preview should match the information density of the existing send confirmation screen — users should have the same confidence level approving agent intents as manual sends
- Hardware wallet flow should be identical whether the transaction originated from the user or an agent — no different UX for agent-signed transactions

</specifics>

<deferred>
## Deferred Ideas

- Batch intents (approve multiple atomically) — AGNT-V2-01, deferred to v2
- Long-poll /subscribe for near-real-time status — AGNT-V2-02, deferred to v2
- Agent-specified TTL / expiration on intents — considered, rejected for v1 (no expiry, user is in control)
- Rejection reason field — considered, rejected for v1 (instant reject, agent can ask through own channel)
- Bulk reject all — considered, rejected for v1 (individual review only, safer for wallet app)
- Intent history / audit trail on Agent API screen — considered, deferred (use normal tx history instead)

</deferred>

---

*Phase: 03-agent-signing-prompt*
*Context gathered: 2026-03-17*
