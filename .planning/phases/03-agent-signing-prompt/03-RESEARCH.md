# Phase 3: Agent Signing Prompt - Research

**Researched:** 2026-03-18
**Domain:** Flutter/Dart UI (bottom sheet, Riverpod, overlay patterns) + Rust FRB bridge (StreamSink intent streaming) + Solana transaction lifecycle (simulate, sign, submit, poll)
**Confidence:** HIGH — all key code read directly; patterns verified from existing codebase, no speculative assumptions

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- Bottom sheet slides up from bottom, covers ~60% of screen, non-blocking (user can dismiss without acting)
- Dismiss = "deal with it later" — intent stays pending; no auto-reject on dismiss
- Auto-show bottom sheet when new intent arrives while app is actively open
- Multiple quick intents: show first, queue rest with "N more pending" indicator on the sheet
- After acting on one, next pending intent slides in automatically
- "Pending Requests" section at top of existing Agent API screen
- Badge count on Agent API sidebar icon showing pending intent count
- Queue row format: "Type + amount + time ago" with [Review] button
- Queue shows pending intents only — once approved/rejected, they disappear (visible in normal tx history)
- No intent expiration — intents stay pending indefinitely
- Individual review only — no bulk reject
- After unlock from idle lock: badge count on sidebar only, no auto-popup
- Rich preview: agent label, intent type header, amount with USD, recipient (truncated middle), simulation status, fee estimate
- Send SOL/Token preview: amount, recipient, fee, simulation status
- Swap preview: input/output amounts + tokens, exchange rate, slippage %, fee, simulation status
- Sign Message preview: raw message as UTF-8 (hex fallback), info banner ("Message signature only. No transaction, no fees."), Approve button labeled "Sign"
- Simulation runs in background; "Simulation: Running..." with spinner; updates in-place
- Approve button enabled immediately — user can approve before simulation completes
- Simulation failure: red warning banner with error + "Approving a failed simulation may result in a lost tx fee" — approve still available
- No app password required for approve (review + tap is the authorization)
- After approve: sheet transitions to progress view: Signing... → Submitting... → Confirmed (with signature)
- Hardware wallet signing: "Connect your ESP32 to sign" if active wallet is hardware type
- On confirmation: auto-dismiss after 3 seconds, then next pending intent if queue non-empty
- On signing/submission failure: show error in sheet with [Retry] and [Dismiss] buttons; intent marked "failed"
- Rejection: instant, no reason field; intent immediately gets "rejected" status

### Claude's Discretion

- Exact bottom sheet animation and drag handle styling
- StreamSink event format for intent notifications from Rust to Dart
- FRB bridge function signatures for intent approval/rejection/status updates
- How to fetch swap quotes/rates for the preview (can reuse existing Jupiter/DFlow integration)
- Intent Dart model structure (mirroring Rust types)
- Badge widget implementation on NavigationRail
- Progress indicator styling during signing lifecycle
- Whether to poll for confirmation or use WebSocket/stream

### Deferred Ideas (OUT OF SCOPE)

- Batch intents (approve multiple atomically) — AGNT-V2-01
- Long-poll /subscribe for near-real-time status — AGNT-V2-02
- Agent-specified TTL / expiration on intents — rejected for v1
- Rejection reason field — rejected for v1
- Bulk reject all — rejected for v1
- Intent history / audit trail on Agent API screen — deferred
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| AGNT-03 | Agent can POST intent (send_sol, send_token, swap, sign_message) | Rust server already has POST /intent with IntentType enum; sign_message MISSING from Rust enum — must be added |
| AGNT-04 | User sees dismissable signing prompt overlay with full preview when app is open | `showModalBottomSheet` established pattern; FRB StreamSink wires intent arrival to Flutter; IntentNotifier drives UI |
| AGNT-05 | Pending intents queue when user is away; user reviews queued list on return | IntentNotifier holds List<PendingIntent>; badge on NavigationRail; Pending Requests section in AgentApiScreen |
| AGNT-06 | Transaction simulation runs in background; prompt updates with results | SolanaRpcClient.simulateTransaction() already proven; run via Future.microtask in IntentNotifier; state update triggers bottom sheet rebuild |
| AGNT-07 | User can approve or reject each intent from the signing prompt | approve_intent/reject_intent already in AgentServer; need FRB bridge exposure; Dart calls bridge then updates local state |
| AGNT-08 | Approved intent is built, signed (software or hardware), and submitted | SendProvider._buildSignedTxSoftware/Hardware pattern reusable; add sign_send_sol/send_token calls via existing send.rs bridge; swap uses existing sign.dart bridge |
| AGNT-09 | Agent can poll intent status (pending → building → signing → submitted → confirmed/failed/rejected) | update_intent_status on AgentServer already exists; IntentNotifier must call it at each lifecycle step |
</phase_requirements>

---

## Summary

Phase 3 is integration work, not greenfield. The Rust agent server already has `approve_intent`, `reject_intent`, `update_intent_status`, and an `intent_sender` mpsc channel waiting to be wired. The Flutter signing pipeline in `SendProvider` is proven and covers software and hardware wallets. The gap is: (1) FRB StreamSink to deliver intents from Rust to Flutter, (2) an IntentNotifier Riverpod provider managing the pending queue, (3) a bottom-sheet signing prompt widget, and (4) a Pending Requests UI section in the Agent API screen.

**Critical gap found in Rust:** `IntentType` in `intent.rs` has `SendSol`, `SendToken`, `Swap`, and `Stake` — but `SignMessage` is absent. AGNT-03 and the ROADMAP both require `sign_message`. Phase 3 must add `SignMessage { message: Vec<u8> }` to the Rust enum before the server can accept it. Similarly, `Stake` is defined in the enum but has no signing path — the planner should scope Stake signing to v2 or document it as not implemented in Phase 3.

The three discretion items with meaningful impact on plan structure are: (1) StreamSink event format — research shows FRB 2.x supports `StreamSink<T>` as a parameter to an `async` Rust function; (2) confirmation polling vs stream — poll (reuse `_pollConfirmation` pattern from SendProvider); (3) swap quote fetching for preview — the agent intent only carries `input_mint`, `output_mint`, `amount`, and `slippage_bps`, which is sufficient for a Jupiter/DFlow quote call matching the existing `fetchQuote()` pattern.

**Primary recommendation:** Add `SignMessage` to Rust IntentType, add 3 FRB bridge functions (`stream_intents`, `approve_intent`, `reject_intent`, `update_intent_status`), build IntentNotifier in Dart, build the bottom-sheet widget, add Pending Requests section to AgentApiScreen, and add badge to NavigationRail.

---

## Standard Stack

### Core (already in project — no new dependencies needed)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter_riverpod | ^2.5.1 | IntentNotifier state management | Established pattern in every provider |
| flutter_rust_bridge | 2.11.1 | StreamSink for intent streaming, bridge calls | Already the FFI layer |
| go_router | ^14.2.0 | Routing (no new routes needed for overlay) | Established routing layer |
| shared_preferences | ^2.2.0 | No new usage needed for Phase 3 | Already in project |

### Flutter SDK (built-in, no dependency)

| Widget/API | Purpose | Notes |
|------------|---------|-------|
| `showModalBottomSheet` | Signing prompt overlay | Already used in pattern references; DraggableScrollableSheet for 60% coverage |
| `OverlayEntry` / global Navigator | Show sheet from anywhere | Required for auto-show when not on Agent API screen |
| `Timer` | Auto-dismiss after 3s, confirmation polling | Already used in SendProvider |

### Supporting (no new packages needed)

The Jupiter/DFlow services already exist for swap quote fetching during preview. No new third-party dependencies needed.

**Installation:** No new packages to install.

---

## Architecture Patterns

### Recommended Project Structure

```
lib/
├── features/agent/
│   ├── agent_api_screen.dart       # MODIFY: add Pending Requests section at top
│   ├── signing_prompt_sheet.dart   # NEW: DraggableScrollableSheet bottom sheet widget
│   └── intent_detail_view.dart     # NEW: per-intent rich preview widget (or inline)
├── providers/
│   ├── agent_provider.dart         # MODIFY: add IntentNotifier, pendingIntentCountProvider
│   └── intent_provider.dart        # NEW (or extend agent_provider.dart): IntentNotifier
├── models/
│   └── intent.dart                 # NEW: Dart intent model mirroring Rust types
└── src/rust/api/
    └── agent.dart                  # MODIFY stub: add stream_intents, approve_intent, etc.

rust/deadbolt_bridge/src/api/
└── agent.rs                        # MODIFY: add intent streaming + approve/reject/update_status

rust/deadbolt_core/src/agent/
└── intent.rs                       # MODIFY: add SignMessage variant to IntentType
```

### Pattern 1: FRB StreamSink for Intent Notifications

**What:** FRB 2.x supports streaming from Rust to Dart via `StreamSink<T>`. A Rust function accepts a `StreamSink<IntentEvent>` and spawns a task that forwards mpsc channel messages into the sink.

**When to use:** Any time Rust needs to push data to Flutter asynchronously without Flutter polling.

**How it works in FRB 2.x:**
```rust
// rust/deadbolt_bridge/src/api/agent.rs
// Source: flutter_rust_bridge 2.x docs — StreamSink pattern
pub async fn stream_intents(
    sink: StreamSink<IntentEvent>,
) -> Result<(), String> {
    // Take the intent_rx from the running server
    // When server starts, store intent_rx in a OnceLock so this function can claim it
    // Forward each received Intent as an IntentEvent to sink
    loop {
        match rx.recv().await {
            Some(intent) => {
                let _ = sink.add(IntentEvent { ... });
            }
            None => break,
        }
    }
    Ok(())
}

pub struct IntentEvent {
    pub id: String,
    pub intent_type_json: String,  // serialize IntentType to JSON string
    pub created_at: u64,
    pub api_token_prefix: String,  // first 10 chars for display
}
```

**Dart side:**
```dart
// In IntentNotifier.build() or a dedicated stream listener
agent_bridge.streamIntents().listen((event) {
  // Add to pending queue
  state = [...state, PendingIntent.fromEvent(event)];
  // Show bottom sheet if app is active
  _maybeShowSigningPrompt();
});
```

**Key FRB constraint:** FRB 2.x `StreamSink` parameter must be the LAST parameter of the Rust function (or a dedicated stream function). The function signature must be `pub async fn`.

### Pattern 2: IntentNotifier (Riverpod AsyncNotifier)

**What:** A Riverpod `Notifier<List<PendingIntent>>` that holds the pending intent queue, manages simulation state per intent, and drives the bottom sheet.

```dart
// lib/models/intent.dart
class PendingIntent {
  final String id;
  final IntentType type;
  final String agentLabel;   // from api_token_prefix lookup
  final int createdAt;
  final SimulationPhase simulationPhase;  // pending | running | success | failed
  final SimulationResult? simulationResult;
  final IntentLifecycle lifecycle;  // pending | signing | submitting | confirmed | failed | rejected

  // ... copyWith, factory fromEvent, etc.
}

sealed class IntentType {}
class SendSolIntent extends IntentType {
  final String to;
  final BigInt lamports;
}
class SendTokenIntent extends IntentType {
  final String to;
  final String mint;
  final BigInt amount;
}
class SwapIntent extends IntentType {
  final String inputMint;
  final String outputMint;
  final BigInt amount;
  final int? slippageBps;
}
class SignMessageIntent extends IntentType {
  final List<int> message;  // raw bytes
}
```

**Notifier lifecycle:**
1. `build()` — subscribe to `streamIntents()`, listen for new intents
2. On new intent: append to list, trigger simulation in background, show sheet if active
3. `approve(id)` — call FRB `approveIntent(id)`, transition to signing lifecycle, reuse send pipeline
4. `reject(id)` — call FRB `rejectIntent(id)`, remove from pending list
5. `updateStatus(id, status)` — call FRB `updateIntentStatus(id, status, sig, err)` at each signing step

### Pattern 3: Global Bottom Sheet via Navigator.overlay

**What:** The signing prompt must be showable from anywhere in the app (not just Agent API screen). The standard approach is to use the root navigator key that already exists in `app_router.dart`.

```dart
// Reference the root navigator key (already declared in app_router.dart)
final _rootNavigatorKey = GlobalKey<NavigatorState>(); // already exists

// In IntentNotifier or a global listener:
void _maybeShowSigningPrompt(PendingIntent intent) {
  final context = _rootNavigatorKey.currentContext;
  if (context == null) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    builder: (ctx) => SigningPromptSheet(intentId: intent.id),
  );
}
```

**Key challenge:** The `_rootNavigatorKey` is currently private in `app_router.dart`. It must be made accessible to IntentNotifier, or IntentNotifier must receive a callback from AppShell. The cleanest approach is to expose it via a `Provider<GlobalKey<NavigatorState>?>`.

### Pattern 4: Sign-and-Submit Pipeline for Intents

**What:** Reuse the proven pattern from `SendProvider._buildSignedTxSoftware/Hardware` and `SwapProvider._getSignedTxBase64`.

**Intent type routing:**
- `SendSol` → call `send.rs` `sign_send_sol` (via existing `bridge.signSendSol`)
- `SendToken` → call `send.rs` `sign_send_token` (via existing `bridge.signSendToken`)
- `Swap` → fetch fresh quote (Jupiter/DFlow), call `sign.rs` `sign_serialized_transaction`
- `SignMessage` → call new FRB function `sign_message(message_bytes)` (needs adding to bridge)
- `Stake` → OUT OF SCOPE for Phase 3 (no signing path exists; show "Unsupported" in UI)

**Status update sequence (mirrors Rust IntentStatus lifecycle):**
```
Approve tapped → call approveIntent(id) → status: Approved
               → call updateIntentStatus(id, Signing) → UI: "Signing..."
               → build + sign tx
               → call updateIntentStatus(id, Submitted) → UI: "Submitting..."
               → sendTransaction → signature obtained
               → poll confirmation
               → call updateIntentStatus(id, Confirmed, sig: sig) → UI: "Confirmed"
               → auto-dismiss after 3s
```

### Pattern 5: Simulation in Background

**What:** Mirrors `SendProvider.simulate()`. Run simulation immediately after intent arrives, update intent state in place.

```dart
Future<void> _runSimulation(String intentId) async {
  // Update simulation state to "running"
  _updateSimulation(intentId, SimulationPhase.running);

  final rpc = SolanaRpcClient(ref.read(networkProvider).rpcUrl);
  try {
    // Build unsigned tx for simulation (software wallet only needed for sim)
    final unsignedBase64 = await _buildUnsignedTx(intentId);
    final result = await rpc.simulateTransaction(unsignedBase64);
    _updateSimulation(intentId,
      result.success ? SimulationPhase.success : SimulationPhase.failed,
      result: result,
    );
  } catch (e) {
    _updateSimulation(intentId, SimulationPhase.failed, error: e.toString());
  } finally {
    rpc.dispose();
  }
}
```

**Key nuance:** `simulateTransaction` in `solana_rpc.dart` already uses `replaceRecentBlockhash: true`, so no fresh blockhash is needed for simulation. Hardware wallet signing is NOT needed for simulation — build an unsigned tx using wallet public key for `from` field only.

### Anti-Patterns to Avoid

- **Storing intent_rx in AGENT_SERVER static after dropping it:** In Phase 2, `_intent_rx` was dropped. Phase 3 must store `intent_rx` in a new static (`OnceLock<Mutex<Option<mpsc::UnboundedReceiver<Intent>>>>`) when the server starts, and `stream_intents` claims it.
- **Calling showModalBottomSheet from a non-UI context:** Always route through the root navigator key. Never call from a Rust callback directly.
- **Blocking the signing pipeline on simulation:** Simulation must be fire-and-forget; approve must remain enabled immediately.
- **Forgetting to call update_intent_status at each step:** The agent's poll response reflects whatever status is stored in AppState.intents. Missing a status update call leaves the agent stuck.
- **Disposing SolanaRpcClient inside a Timer callback before confirmation:** Use the same `_pollConfirmation` guard as SendProvider (timer.tick > 30 safety valve).
- **Running Stake signing in Phase 3:** No signing infrastructure exists for Stake; render "Unsupported" in the preview and reject automatically with a descriptive error.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Transaction simulation | Custom simulation logic | `SolanaRpcClient.simulateTransaction()` | Already handles `replaceRecentBlockhash`, proven in production |
| Software wallet signing | Custom Ed25519 | `bridge.signSendSol/signSendToken` or `sign_bridge.signSerializedTransaction` | Handles key unlock, zeroization, hardware path |
| Swap quote for preview | Custom HTTP call to Jupiter | `JupiterService.getQuote()` + `DFlowService.getQuote()` | Already implemented, handles API keys, error handling |
| Confirmation polling | WebSocket subscription | `_pollConfirmation` pattern from `SendProvider` | Already battle-tested; WS adds complexity without v1 benefit |
| Intent state serialization | Custom serde impl | Use `serde_json::to_string` on Rust enums with existing derives | IntentType already has `#[serde(tag = "type", rename_all = "snake_case")]` |
| Bottom sheet sizing | Custom overlay/window | `showModalBottomSheet` + `DraggableScrollableSheet` | Flutter standard, handles dismiss gesture, backdrop tap |

**Key insight:** The single most dangerous custom-build temptation is the intent streaming mechanism. FRB 2.x `StreamSink` is the correct and supported approach — do not implement polling from Flutter into Rust as a workaround.

---

## Common Pitfalls

### Pitfall 1: intent_rx Was Dropped in Phase 2

**What goes wrong:** `_intent_rx` was explicitly dropped in `start_agent_server` in Phase 2 (documented decision). If Phase 3 tries to receive from the channel, it will immediately get `None` (channel closed from receiver side).

**Why it happens:** Dropping the receiver closes the unbounded channel. The sender (`intent_sender`) will silently discard sent messages (no panic, just `Err(SendError)` which was `let _ =` suppressed).

**How to avoid:** Phase 3 must modify `start_agent_server` to store `intent_rx` in a new static (`OnceLock<Mutex<Option<UnboundedReceiver<Intent>>>>`) before dropping the old approach. The `stream_intents` FRB function then claims this receiver.

**Warning signs:** `sink.add(...)` never fires; Flutter never receives intent events.

### Pitfall 2: StreamSink Lifetime vs Server Restart

**What goes wrong:** If the agent server is stopped and restarted, a new `intent_rx` is created. But the old `stream_intents` stream may still be alive, or a new one may not be subscribed yet.

**How to avoid:** When the server restarts, either: (a) cancel the old stream subscription and start a new one, or (b) design `stream_intents` to be a long-lived global subscription that survives server restarts by resubscribing internally. Option (b) is simpler — the IntentNotifier listens once during app lifetime and the Rust side re-starts forwarding from the new receiver.

**Recommendation:** Store intent_rx in a static that `stream_intents` reads from. When server restarts, update the static. The stream task re-polls the new receiver. Use `tokio::select!` on shutdown to cleanly drop on stop.

### Pitfall 3: showModalBottomSheet Context Availability

**What goes wrong:** If a new intent arrives while the app is showing a modal (lock screen, another dialog), `showModalBottomSheet` may fail silently or overlap incorrectly.

**How to avoid:** Guard the auto-show with a check: only show if `ModalRoute.of(context)?.isCurrent == true` and the app is not locked. If locked, rely on the badge + queue (which is the locked-state behavior per CONTEXT.md).

**Warning signs:** Multiple bottom sheets stacked on top of each other; sheet appears under lock screen.

### Pitfall 4: SignMessage Missing from Rust IntentType

**What goes wrong:** AGNT-03 requires `sign_message` intent type. The Rust `IntentType` enum only has `SendSol`, `SendToken`, `Swap`, `Stake`. The server will return a 400 parse error on any `sign_message` POST.

**How to avoid:** Add `SignMessage { message: String }` (hex-encoded bytes) to `IntentType` in `intent.rs` before any other Phase 3 work. The CONTEXT.md preview describes rendering it as UTF-8 bytes, so the Dart side decodes from hex.

**Alternative encoding:** Use `message: String` as hex in the Rust API (clean JSON serialization) and decode to `List<int>` in Dart.

### Pitfall 5: Swap Intent Needs a Live Quote for Preview

**What goes wrong:** The `Swap` IntentType only carries `input_mint`, `output_mint`, `amount`, `slippage_bps`. The rich preview requires "expected output amount and token, exchange rate." Without a live quote, these fields are empty.

**How to avoid:** When a Swap intent arrives, fire `JupiterService.getQuote()` (or DFlow) asynchronously alongside simulation. Store the quote result in the `PendingIntent` model. Display "Fetching quote..." until it arrives.

**Edge case:** Quote may fail (network error, unsupported pair). Render "Quote unavailable" in those fields — the user can still approve/reject.

### Pitfall 6: Hardware Wallet Simulation Path

**What goes wrong:** `SendProvider.simulate()` calls `_ensureUnlocked(address)` before building a signed tx for simulation. For hardware wallets, `_isHardwareWallet` is true and `_ensureUnlocked` is skipped — but `_buildSignedTxHardware` requires physical device interaction, making simulation block the UI waiting for ESP32.

**How to avoid:** For simulation only, build an unsigned transaction using the wallet's public key (no private key needed). The `simulateTransaction` RPC call already uses `sigVerify: false`. Build a dummy-signed or unsigned tx variant for simulation purposes without touching the hardware.

**Implementation:** The intent simulation should use a different code path from approval signing. For simulation: build tx bytes with `from` public key only, submit unsigned to `simulateTransaction` (sigVerify: false accepts it). This mirrors the existing `simulateTransaction` behavior which accepts unsigned transactions.

### Pitfall 7: NavigationRail Badge Requires Widget Wrapping

**What goes wrong:** Flutter's `NavigationRailDestination` has an `icon` property but no built-in badge. Naively setting the icon to a `Badge` widget from Material 3 may cause layout issues or not animate badge count changes.

**How to avoid:** Use Flutter's `Badge` widget (available since Flutter 3.x / Material 3) wrapping the icon. Watch `pendingIntentCountProvider` in `AppShell.build()` and conditionally wrap the Agent API destination icon.

```dart
NavigationRailDestination(
  icon: Badge(
    isLabelVisible: pendingCount > 0,
    label: Text('$pendingCount'),
    child: Icon(Icons.lan_outlined),
  ),
  // ...
)
```

This is a pure Flutter built-in — no package needed. The Badge widget is available in `flutter/material.dart` since Material 3 (Flutter 3.7+). This project targets SDK ^3.11.1, which is well above that.

### Pitfall 8: FRB Stub Must Be Updated Before Codegen

**What goes wrong:** `lib/src/rust/api/agent.dart` is a typed stub that will be overwritten by FRB codegen. If the stub does not include the new functions (`streamIntents`, `approveIntent`, `rejectIntent`, `updateIntentStatus`), code that calls them will throw `UnimplementedError` in the stub phase and compile errors after codegen.

**How to avoid:** Add all new functions to the stub immediately after adding them to the Rust bridge, following the established pattern from Phase 2 (`agent.dart` stub).

---

## Code Examples

Verified patterns from existing codebase:

### StreamSink Registration Pattern in FRB 2.x
```rust
// Source: FRB 2.x — function accepts StreamSink as parameter, async fn required
// Add to rust/deadbolt_bridge/src/api/agent.rs

static INTENT_RX: OnceLock<Mutex<Option<mpsc::UnboundedReceiver<Intent>>>> = OnceLock::new();

fn intent_rx_store() -> &'static Mutex<Option<mpsc::UnboundedReceiver<Intent>>> {
    INTENT_RX.get_or_init(|| Mutex::new(None))
}

// Called after AgentServer::start() — store the receiver
fn store_intent_rx(rx: mpsc::UnboundedReceiver<Intent>) {
    if let Ok(mut guard) = intent_rx_store().lock() {
        *guard = Some(rx);
    }
}

pub async fn stream_intents(sink: StreamSink<IntentEvent>) -> Result<(), String> {
    let rx = {
        let mut guard = intent_rx_store().lock().map_err(|e| e.to_string())?;
        guard.take()
    };
    let mut rx = rx.ok_or_else(|| "No intent receiver — start server first".to_string())?;

    loop {
        match rx.recv().await {
            Some(intent) => {
                let event = IntentEvent {
                    id: intent.id.clone(),
                    intent_type_json: serde_json::to_string(&intent.intent_type)
                        .unwrap_or_default(),
                    created_at: intent.created_at,
                    api_token_prefix: if intent.api_token.len() >= 10 {
                        intent.api_token[..10].to_string()
                    } else {
                        intent.api_token.clone()
                    },
                };
                if sink.add(event).is_err() {
                    // Dart side closed — put rx back and return
                    break;
                }
            }
            None => break,  // channel closed (server stopped)
        }
    }
    Ok(())
}
```

### FRB approve/reject/update_status Bridge Functions
```rust
// rust/deadbolt_bridge/src/api/agent.rs

pub fn approve_intent(intent_id: String) -> Result<(), String> {
    let guard = agent_server().lock().map_err(|e| e.to_string())?;
    let server = guard.as_ref().ok_or("Server not running")?;
    server.approve_intent(&intent_id).map_err(|e| e.to_string())
}

pub fn reject_intent(intent_id: String) -> Result<(), String> {
    let guard = agent_server().lock().map_err(|e| e.to_string())?;
    let server = guard.as_ref().ok_or("Server not running")?;
    server.reject_intent(&intent_id).map_err(|e| e.to_string())
}

pub fn update_intent_status(
    intent_id: String,
    status: String,   // "signing" | "submitted" | "confirmed" | "failed"
    signature: Option<String>,
    error: Option<String>,
) -> Result<(), String> {
    use deadbolt_core::agent::intent::IntentStatus;
    let parsed_status = match status.as_str() {
        "signing"   => IntentStatus::Signing,
        "submitted" => IntentStatus::Submitted,
        "confirmed" => IntentStatus::Confirmed,
        "failed"    => IntentStatus::Failed,
        other => return Err(format!("Unknown status: {other}")),
    };
    let guard = agent_server().lock().map_err(|e| e.to_string())?;
    let server = guard.as_ref().ok_or("Server not running")?;
    server.update_intent_status(&intent_id, parsed_status, signature, error)
        .map_err(|e| e.to_string())
}
```

### SignMessage Addition to Rust IntentType
```rust
// rust/deadbolt_core/src/agent/intent.rs — add to IntentType enum
SignMessage {
    message: String,  // hex-encoded bytes; Dart decodes to List<int> for UTF-8 attempt
},
```

### Badge on NavigationRail Destination
```dart
// lib/shared/app_shell.dart — in build(), watch pendingIntentCountProvider
final pendingCount = ref.watch(pendingIntentCountProvider);

// Replace Agent API destination icon:
NavigationRailDestination(
  icon: Badge(
    isLabelVisible: pendingCount > 0,
    label: Text('$pendingCount', style: TextStyle(fontSize: 10)),
    child: const Icon(Icons.lan_outlined),
  ),
  selectedIcon: Badge(
    isLabelVisible: pendingCount > 0,
    label: Text('$pendingCount', style: TextStyle(fontSize: 10)),
    child: const Icon(Icons.lan),
  ),
  label: const Text('Agent API'),
),
```

### Bottom Sheet with DraggableScrollableSheet (~60% coverage)
```dart
// lib/features/agent/signing_prompt_sheet.dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,   // required for DraggableScrollableSheet
  isDismissible: true,        // swipe down = dismiss (keep pending)
  backgroundColor: Colors.transparent,
  builder: (ctx) => DraggableScrollableSheet(
    initialChildSize: 0.6,
    minChildSize: 0.4,
    maxChildSize: 0.9,
    expand: false,
    builder: (ctx, scrollController) => SigningPromptSheet(
      intentId: intentId,
      scrollController: scrollController,
    ),
  ),
);
```

### Intent Dart Model
```dart
// lib/models/intent.dart
enum IntentLifecycle { pending, signing, submitting, confirmed, failed, rejected }
enum SimulationPhase { idle, running, success, failed }

class PendingIntent {
  final String id;
  final AgentIntentType type;
  final String agentTokenPrefix;
  final int createdAt;
  final SimulationPhase simulationPhase;
  final String? simulationError;
  final int? simulationUnitsConsumed;
  final IntentLifecycle lifecycle;
  final String? txSignature;
  final String? errorMessage;
  // Swap preview fields (loaded asynchronously)
  final SwapQuotePreview? swapQuote;

  // factory PendingIntent.fromEvent(IntentEvent e) — parses intent_type_json
  // copyWith(...)
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| FRB v1 `SyncReturn` for streams | FRB v2 `StreamSink<T>` parameter | FRB 2.0 (2024) | StreamSink is first-class; Dart gets a `Stream<T>` directly |
| Manual polling Rust state from Flutter | StreamSink push from Rust | FRB 2.x | Eliminates polling overhead for real-time events |
| Flutter `showBottomSheet` | `showModalBottomSheet` + `DraggableScrollableSheet` | Flutter 2.x+ | Draggable sheet gives proper 60% sizing with gesture dismiss |
| Custom badge overlay | Flutter Material 3 `Badge` widget | Flutter 3.7+ | Built-in, animated, no package needed |

**Deprecated/outdated:**
- `flutter_rust_bridge` v1 API style: This project uses FRB 2.11.1 — all bridge patterns must use v2 style (no `SyncReturn`, use `#[frb(sync)]` attribute instead)

---

## Open Questions

1. **Stake intent in Phase 3**
   - What we know: `Stake { amount_lamports, lst_mint }` exists in IntentType. No signing path exists in the bridge or in `send.rs`/`sign.rs`.
   - What's unclear: Whether Phase 3 should show an "unsupported" banner and auto-reject, or simply not register Stake as a displayable type.
   - Recommendation: Show Stake intents in the queue with an "Unsupported in this version" preview and auto-reject via `reject_intent` with a descriptive error set on the intent. Agent polling sees `rejected` status.

2. **Navigator key accessibility for global bottom sheet**
   - What we know: `_rootNavigatorKey` is private in `app_router.dart`. IntentNotifier needs it to show the sheet from anywhere.
   - What's unclear: Whether to expose via a Provider, pass as a callback, or use a different pattern.
   - Recommendation: Expose `_rootNavigatorKey` via a `Provider<GlobalKey<NavigatorState>?>` in `app_router.dart`. This is clean, testable, and follows established project patterns.

3. **Simulation for hardware wallet intents — unsigned tx building**
   - What we know: `simulateTransaction` accepts `sigVerify: false` and `replaceRecentBlockhash: true`. An unsigned tx is acceptable for simulation.
   - What's unclear: Whether the Rust side can build an unsigned tx for SendSol/SendToken without the private key, or if it needs a dummy signature.
   - Recommendation: Use `simulateTransaction` with `replaceRecentBlockhash: true` and pass a transaction with zeroed signature bytes (the RPC accepts this with sigVerify false). The existing `solana_rpc.dart` call already sets these flags. Build the tx in Rust using just the public key for `from`, leave signature as zeros.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (built-in SDK) + Rust `#[test]` |
| Config file | none — flutter_test is implicit; Rust uses `#[cfg(test)]` modules inline |
| Quick run command (Flutter) | `flutter test test/` |
| Quick run command (Rust) | `cd rust && cargo test -p deadbolt_core` |
| Full suite command | `flutter test test/ && cd rust && cargo test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AGNT-03 | SignMessage added to IntentType; server parses sign_message POST | unit (Rust) | `cd rust && cargo test -p deadbolt_core agent::intent` | ❌ Wave 0 |
| AGNT-03 | IntentType all variants round-trip through serde | unit (Rust) | `cd rust && cargo test -p deadbolt_core agent::intent::tests` | ❌ Wave 0 |
| AGNT-04 | PendingIntent model parses intent_type_json for all variants | unit (Dart) | `flutter test test/intent_model_test.dart` | ❌ Wave 0 |
| AGNT-04 | SigningPromptSheet renders without error | widget (Dart) | `flutter test test/signing_prompt_sheet_test.dart` | ❌ Wave 0 |
| AGNT-05 | pendingIntentCountProvider returns 0 with empty queue | unit (Dart) | `flutter test test/intent_provider_test.dart` | ❌ Wave 0 |
| AGNT-05 | Badge shows/hides based on pending count | widget (Dart) | `flutter test test/app_shell_badge_test.dart` | ❌ Wave 0 |
| AGNT-06 | simulateTransaction call with replaceRecentBlockhash=true | manual (needs live RPC) | manual | N/A |
| AGNT-07 | approve_intent / reject_intent bridge functions | unit (Rust) | `cd rust && cargo test -p deadbolt_core agent::server::tests::test_approve_reject_intent` | ✅ (existing test) |
| AGNT-07 | Dart notifier state transitions on approve/reject | unit (Dart) | `flutter test test/intent_provider_test.dart` | ❌ Wave 0 |
| AGNT-08 | Sign-and-submit pipeline calls update_intent_status at each step | manual + integration | manual E2E | N/A |
| AGNT-09 | update_intent_status sets correct IntentStatus on server | unit (Rust) | `cd rust && cargo test -p deadbolt_core agent::server` | ✅ (existing test covers update) |

### Sampling Rate

- **Per task commit:** `flutter test test/ && cd rust && cargo test -p deadbolt_core`
- **Per wave merge:** `flutter test test/ && cd rust && cargo test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/intent_model_test.dart` — covers AGNT-03/AGNT-04 (PendingIntent parsing, all IntentType variants)
- [ ] `test/intent_provider_test.dart` — covers AGNT-05/AGNT-07 (state transitions, queue management)
- [ ] `test/signing_prompt_sheet_test.dart` — covers AGNT-04 (widget smoke test, no FRB calls needed)
- [ ] `test/app_shell_badge_test.dart` — covers AGNT-05 (badge visibility based on pendingIntentCountProvider)
- [ ] Rust: `intent.rs` serde test for new `SignMessage` variant — covers AGNT-03

---

## Sources

### Primary (HIGH confidence)

- Direct read: `rust/deadbolt_core/src/agent/intent.rs` — IntentType enum, IntentStatus lifecycle, Intent struct
- Direct read: `rust/deadbolt_core/src/agent/server.rs` — AppState, approve_intent, reject_intent, update_intent_status, intent_sender, submit_intent_handler
- Direct read: `rust/deadbolt_bridge/src/api/agent.rs` — FRB bridge patterns, OnceLock singleton, existing DTO types
- Direct read: `lib/providers/send_provider.dart` — signAndSubmit pipeline, _buildSignedTxSoftware/Hardware, _pollConfirmation, TxStatus state machine
- Direct read: `lib/providers/swap_provider.dart` — fetchQuote pattern, _getSignedTxBase64, sign_serialized_transaction usage
- Direct read: `lib/services/solana_rpc.dart` — simulateTransaction (replaceRecentBlockhash: true, sigVerify: false)
- Direct read: `lib/shared/app_shell.dart` — NavigationRail destinations array, AppShell ConsumerStatefulWidget structure
- Direct read: `lib/features/agent/agent_api_screen.dart` — AgentApiScreen ListView structure, existing sections
- Direct read: `lib/providers/agent_provider.dart` — AgentServerNotifier, AgentKeyNotifier patterns
- Direct read: `lib/routing/app_router.dart` — _rootNavigatorKey, ShellRoute, GoRouter structure
- Direct read: `lib/models/send.dart` — TxStatus enum, SendState copyWith pattern
- Direct read: `pubspec.yaml` — flutter_rust_bridge 2.11.1, flutter_riverpod ^2.5.1, Flutter SDK ^3.11.1
- Direct read: `rust/deadbolt_bridge/src/frb_generated.rs` — `default_stream_sink_codec = SseCodec` confirms StreamSink is used with SSE codec

### Secondary (MEDIUM confidence)

- FRB 2.x documentation: StreamSink parameter-based streaming is the canonical FRB 2.x pattern for Rust-to-Dart push; confirmed by presence of `default_stream_sink_codec = SseCodec` in generated code indicating the project's FRB setup supports it
- Flutter Material 3 `Badge` widget: available since Flutter 3.7+; project targets SDK ^3.11.1, confirmed compatible
- `DraggableScrollableSheet` + `showModalBottomSheet(isScrollControlled: true)`: standard Flutter pattern for ~60% height bottom sheets with drag-to-dismiss

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all dependencies already in project, no new packages needed
- Architecture: HIGH — all patterns read directly from codebase; FRB StreamSink confirmed by generated code
- Pitfalls: HIGH — AGNT-rx-dropped is a documented decision; sign_message gap confirmed by direct read of intent.rs; others derived from existing code analysis

**Research date:** 2026-03-18
**Valid until:** 2026-04-18 (stable Rust/Flutter stack; FRB version pinned)
