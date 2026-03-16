# Phase 2: Agent API Bridge - Research

**Researched:** 2026-03-16
**Domain:** FRB 2.11.1 bridge layer, axum 0.8, Flutter Riverpod state management, server lifecycle
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Server Lifecycle**
- Auto-start if previously enabled — if user had the server running when they last closed the app, it starts automatically on next launch; off by default for first-time users
- Server toggle lives on the Agent API landing page (not Settings)
- Port binding uses SO_REUSEADDR to reclaim port from TIME_WAIT state after crash recovery; if port is truly in use by another process, show error
- Server errors surface as inline status on the Agent API page (red indicator + error message), no popups or toasts
- Server status indicator: green "Running on :9876" / red "Error: [message]" / gray "Stopped"

**API Key Management UX**
- Keys are masked by default (db_••••x7f2) but revealable with auth challenge (app password)
- Optional user-defined labels at creation (e.g., "Claude agent", "Trading bot"); blank defaults to "API Key 1", "API Key 2", etc.
- Soft limit of 10 keys
- Revocation: swipe-to-delete on key row, then confirm dialog, requires auth challenge (per Phase 1 decision: create/delete API key requires password)
- Key creation also requires auth challenge
- Full key shown once at creation in a copyable dialog; afterward, masked unless user reveals with password

**Agent API Landing Page**
- All-in-one dashboard: server toggle + status at top, API keys list in middle, curl test section at bottom — single scrollable page, no sub-navigation
- Empty state (no keys): guided setup with explanation text and prominent "Create Your First Key" button; server toggle visible but disabled until a key exists
- Quick Test section: dropdown selector with all available endpoints (/health, /wallet, /balance, /tokens, /price, /history); selecting one generates the full curl command with the user's real bearer token; copy button
- Sidebar position: after Contacts, before Settings (Dashboard → History → Contacts → Agent API → Settings)

**Query Endpoint Responses**
- /wallet — returns wallet address
- /balance — SOL balance + all SPL token balances with mint addresses + USD values
- /tokens — SPL token list with balances, mint addresses, metadata
- /price?mints=... — current USD prices for requested mints
- /history — last 20 transactions by default; supports ?limit=N (max 100) and ?before=signature
- /health — existing health check (status, version)
- No NFT endpoint in Phase 2

### Claude's Discretion
- StreamSink event format and DTO structure for Rust→Dart bridge
- FRB bridge singleton pattern (can follow existing OnceLock<RwLock<>> from wallet.rs)
- Exact Agent API page layout spacing and styling (follow existing brand theme)
- curl command formatting and which key is pre-selected in the dropdown
- Whether /tokens and /balance share underlying data fetch or call separately
- Error response JSON structure for query endpoints

### Deferred Ideas (OUT OF SCOPE)
- NFT query endpoint — add later if agents need it
- Batch intents — AGNT-V2-01, deferred to v2
- Long-poll /subscribe endpoint — AGNT-V2-02, deferred to v2
- Remote bridge service — AGNT-V2-03, deferred to v2
- Intent posting (POST /intent) and signing prompt UI — Phase 3 scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| AGNT-01 | Embedded HTTP server starts on localhost:9876 when user enables it | AgentServer.start() already exists; need FRB async wrapper + OnceLock<Mutex<AgentServer>> singleton in api/agent.rs |
| AGNT-02 | Agent authenticates with bearer token (db_ prefix) | auth_middleware already wired via constant_time_eq; need new query endpoints behind the same middleware |
| AGNT-10 | Query endpoints available without approval: wallet, balance, tokens, price, history | Five new axum route handlers needed in server.rs; /wallet handler exists as template |
| AGNT-11 | User can create API keys (shown once, then masked) | AppConfig.api_tokens persists to config.json; FRB bridge functions for create/list/mask; key gen via rand::thread_rng |
| AGNT-12 | User can revoke API keys | Bridge function removes from AppConfig.api_tokens + config.save(); live AppState.api_tokens Mutex must also be updated |
| AGNT-13 | Quick test section generates copy-paste curl command with user's real token | Flutter UI: dropdown + Dart string formatting; no Rust needed |
| AGNT-14 | Agent API has its own sidebar entry | NavigationRail +1 destination in app_shell.dart; GoRoute /agent-api in ShellRoute |
| AGNT-15 | Server status indicator shows running/stopped state | StreamSink<AgentServerEvent> or Riverpod AsyncNotifier polling bridge sync call |
| INFR-05 | Axum server migrated to 0.8 route syntax | server.rs already uses axum 0.8 syntax (/{id} curly brace) — verified; no migration work needed |
| INFR-08 | Axum server properly shuts down on app close | window_manager package (already in pubspec) + lifecycle hook to call stop_agent_server() FRB; oneshot channel already in AgentServer |
</phase_requirements>

---

## Summary

This phase bridges the already-implemented Rust `AgentServer` (in `deadbolt_core/src/agent/`) to the Flutter UI through a new FRB module `deadbolt_bridge/src/api/agent.rs`. The core HTTP server code, auth middleware, and graceful shutdown mechanism are all complete. What is missing is: (1) the FRB bridge layer that exposes start/stop/key-management to Dart, (2) five new query route handlers in the server (`/balance`, `/tokens`, `/price`, `/history`, plus the existing `/wallet`), (3) the Agent API Flutter screen with server toggle, key list, and curl test section, and (4) the shutdown lifecycle hook to reclaim port 9876 on app close.

INFR-05 is already done — `server.rs` uses axum 0.8 `{id}` curly-brace syntax throughout. No migration work needed; this requirement can be marked complete during implementation verification. INFR-08 requires wiring `window_manager` (already in pubspec.yaml) to call `stop_agent_server()` before the window closes.

**Primary recommendation:** Build in three clean layers — (1) Rust: new query handlers + FRB bridge module, (2) Dart providers: AgentServerNotifier with StreamSink status, AgentKeyManager, (3) Flutter UI: AgentApiScreen as a single scrollable page. The existing `OnceLock<RwLock<WalletManager>>` pattern from `wallet.rs` is the exact pattern to follow for the `AgentServer` singleton.

---

## Standard Stack

### Core (already in project, confirmed by inspection)

| Library | Version | Purpose | Confirmed In |
|---------|---------|---------|-------------|
| flutter_rust_bridge | 2.11.1 | FFI + StreamSink bridge | pubspec.yaml, deadbolt_bridge/Cargo.toml |
| axum | 0.8 | HTTP server for agent API | deadbolt_core/Cargo.toml |
| tokio | 1 (full features) | Async runtime; axum runs on FRB's runtime | deadbolt_core/Cargo.toml |
| flutter_riverpod | ^2.5.1 | State management for all Dart providers | pubspec.yaml |
| go_router | ^14.2.0 | Navigation + /agent-api route | pubspec.yaml |
| window_manager | ^0.3.9 | Intercept window close for graceful shutdown | pubspec.yaml — already present |
| shared_preferences | ^2.2.0 | Persist `agent_server_enabled` flag | pubspec.yaml |

### Supporting (for new Rust functionality)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| socket2 | (tokio transitive dep) | SO_REUSEADDR on TcpListener | Server start binding; use `socket2::Socket` then `TcpListener::from_std()` |
| rand | 0.8 | CSPRNG for API key body generation | Key creation (32 bytes → hex = 64-char key body) |
| uuid | 1 (v4 feature) | Already used for intent IDs | Not needed for keys; use rand instead |
| serde_json | 1 | JSON query endpoint responses | Already a dep in deadbolt_bridge |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SO_REUSEADDR via socket2 | Port fallback (9876→9877) | socket2 approach is cleaner; fallback adds complexity and agents need to discover the port |
| StreamSink for server status | Dart polling an FRB sync fn | StreamSink is zero-latency push; polling wastes CPU and requires timer management |
| Riverpod Notifier for key management | BLoC | Notifier is already the established pattern in this project; no reason to deviate |

**Installation:** No new packages needed — all dependencies already present.

---

## Architecture Patterns

### Recommended File Structure (new files only)

```
rust/deadbolt_bridge/src/api/
├── agent.rs             NEW — FRB bridge: start/stop server, key CRUD, StreamSink
└── mod.rs               MODIFY — add `pub mod agent;`

rust/deadbolt_core/src/agent/
└── server.rs            MODIFY — add /balance, /tokens, /price, /history handlers

lib/
├── features/agent/
│   └── agent_api_screen.dart    NEW — single scrollable dashboard page
├── providers/
│   └── agent_provider.dart      NEW — AgentServerNotifier + AgentKeyNotifier
└── routing/
    └── app_router.dart          MODIFY — add /agent-api route in ShellRoute
lib/shared/app_shell.dart        MODIFY — add 5th NavigationRail destination
```

### Pattern 1: AgentServer FRB Singleton

**What:** `OnceLock<Mutex<Option<AgentServer>>>` in `api/agent.rs` — same shape as `OnceLock<RwLock<WalletManager>>` in `wallet.rs`. The `Option<AgentServer>` is `None` when stopped, `Some(server)` when running.

**Why RwLock vs Mutex:** `WalletManager` uses `RwLock` because reads are frequent and writes are rare. `AgentServer` uses `Mutex<Option<>>` because start/stop are the only operations and we need exclusive access to `take()` the `Option` on stop.

**Example:**
```rust
// Source: pattern from rust/deadbolt_bridge/src/api/wallet.rs
static AGENT_SERVER: OnceLock<Mutex<Option<AgentServer>>> = OnceLock::new();

fn agent_server() -> &'static Mutex<Option<AgentServer>> {
    AGENT_SERVER.get_or_init(|| Mutex::new(None))
}

pub async fn start_agent_server(
    tokens: Vec<String>,
    sink: StreamSink<AgentStatusEventDto, SseCodec>,
) -> Result<(), String> {
    let mut guard = agent_server().lock().map_err(|e| e.to_string())?;
    if guard.is_some() {
        return Ok(()); // Already running
    }
    let (server, _rx) = AgentServer::start(9876, tokens, GuardrailsConfig::default(), None)
        .await
        .map_err(|e| e.to_string())?;
    *guard = Some(server);
    // Send Running status event via sink
    let _ = sink.add(AgentStatusEventDto::running(9876));
    Ok(())
}

#[flutter_rust_bridge::frb(sync)]
pub fn stop_agent_server() {
    if let Ok(mut guard) = agent_server().lock() {
        if let Some(mut server) = guard.take() {
            server.stop(); // Sends shutdown oneshot; Drop also calls stop()
        }
    }
}
```

### Pattern 2: StreamSink for Server Status Events

**What:** FRB 2.11.1 supports `StreamSink<T, SseCodec>` for Rust-to-Dart event push. The bridge function subscribes a StreamSink and fires events on server start, stop, and error. The Dart provider converts this to a `Stream<AgentServerStatus>` that the UI watches.

**When to use:** Server status changes (running/stopped/error). Do NOT use for the query endpoint results — those are synchronous FRB calls from Dart.

**Example:**
```rust
// Source: flutter_rust_bridge v2 StreamSink documentation
// In api/agent.rs
pub async fn subscribe_agent_status(
    sink: StreamSink<AgentStatusEventDto, SseCodec>,
) -> Result<(), String> {
    // Store sink in a separate static for later use when status changes
    // Initial state: fire current status immediately
    let is_running = agent_server().lock().map(|g| g.is_some()).unwrap_or(false);
    let _ = sink.add(if is_running {
        AgentStatusEventDto { status: "running".into(), port: Some(9876), error: None }
    } else {
        AgentStatusEventDto { status: "stopped".into(), port: None, error: None }
    });
    Ok(())
}
```

```dart
// In agent_provider.dart
final agentStatusProvider = StreamProvider<AgentServerStatus>((ref) {
    return subscribeAgentStatus();
});
```

### Pattern 3: SO_REUSEADDR via socket2

**What:** Use the `socket2` crate to create a `TcpSocket` with `SO_REUSEADDR` enabled before binding, then convert to a `tokio::net::TcpListener`. This reclaims TIME_WAIT ports after crash/forced close without risking conflicts with actually-running processes.

**Why:** `tokio::net::TcpListener::bind()` does not expose `SO_REUSEADDR` directly. The `socket2` crate is already a transitive dependency (mio → socket2) and available without adding it to Cargo.toml explicitly. If it needs to be explicit, add `socket2 = "0.5"`.

**Example:**
```rust
// Source: socket2 crate documentation + tokio std conversion pattern
use socket2::{Socket, Domain, Type};
use std::net::SocketAddr;

async fn bind_with_reuse(addr: &str) -> Result<tokio::net::TcpListener, DeadboltError> {
    let addr: SocketAddr = addr.parse()
        .map_err(|e| DeadboltError::StorageError(format!("Bad address: {e}")))?;
    let socket = Socket::new(Domain::IPV4, Type::STREAM, None)
        .map_err(|e| DeadboltError::StorageError(format!("Socket create: {e}")))?;
    socket.set_reuse_address(true)
        .map_err(|e| DeadboltError::StorageError(format!("SO_REUSEADDR: {e}")))?;
    socket.set_nonblocking(true)
        .map_err(|e| DeadboltError::StorageError(format!("nonblocking: {e}")))?;
    socket.bind(&addr.into())
        .map_err(|e| DeadboltError::StorageError(format!("Bind {addr}: {e}")))?;
    socket.listen(128)
        .map_err(|e| DeadboltError::StorageError(format!("Listen: {e}")))?;
    tokio::net::TcpListener::from_std(socket.into())
        .map_err(|e| DeadboltError::StorageError(format!("TcpListener: {e}")))
}
```

### Pattern 4: Window Close Lifecycle Hook (INFR-08)

**What:** `window_manager` (already in pubspec.yaml) provides `WindowListener` with `onWindowClose`. Override it to call `stopAgentServer()` synchronously before allowing the close.

**Example:**
```dart
// In main.dart or AppShell — wherever WindowListener is registered
@override
void onWindowClose() async {
    // Synchronous FRB call — stop() is #[frb(sync)]
    stopAgentServer();
    await windowManager.destroy();
}
```

### Pattern 5: API Key Generation and Storage

**What:** Keys are generated in Rust as 32 cryptographically random bytes encoded as lowercase hex, then prefixed with `db_`. Format: `db_` + 64 hex chars = 67 total chars. Keys are stored in `AppConfig.api_tokens` (which persists to `~/.deadbolt/config.json` with 0o600 permissions). Labels are stored alongside tokens in a new `api_key_labels` field (or a `Vec<ApiKeyEntry>` struct replacing the bare `Vec<String>`).

**Important note on AppConfig schema change:** `AppConfig.api_tokens` is currently `Vec<String>`. To support labels, this needs to become `Vec<ApiKeyEntry>` where `ApiKeyEntry { token: String, label: String, created_at: u64 }`. This is a **breaking change to config.json** — need backwards-compat deserialization. Either: (a) keep `api_tokens: Vec<String>` and add a parallel `api_key_labels: HashMap<String, String>` field (both have `#[serde(default)]` so old configs parse fine), or (b) add `#[serde(default)]` to `api_key_entries: Vec<ApiKeyEntry>` and migrate in code. Option (a) is simpler and lower risk.

**Key masking logic:**
```dart
// In Dart — masking is display-only, done in Flutter
String maskKey(String token) {
    // "db_abc123def456..." → "db_••••456"
    if (token.length <= 6) return '••••';
    return '${token.substring(0, 3)}••••${token.substring(token.length - 3)}';
}
```

### Pattern 6: New Query Route Handlers

**What:** Five new route handlers in `deadbolt_core/src/agent/server.rs`. All require valid bearer token (behind existing `auth_middleware`). Data comes from `WalletManager` via the bridge layer passing data at server start — or better, via a data callback approach.

**Critical design choice:** The axum handlers need live wallet data (balances, tokens, history). `AppState` currently only has `wallet_address`. Two approaches:
1. Pass a `Arc<RwLock<WalletManager>>` into `AppState` — direct access to all wallet data (HIGH coupling to Rust internals)
2. Store cached data in `AppState` that the bridge layer updates when balances refresh — the handler returns the cached snapshot

**Recommendation (from architecture research):** Use approach 2 with cached data in AppState. The bridge layer calls `update_agent_server_data(balance, tokens, history)` after each data refresh. Handlers return the cached snapshot. This avoids tight coupling and works well since the agent only needs reasonably-fresh data.

```rust
// Extended AppState in server.rs
pub struct AppState {
    pub api_tokens: Mutex<Vec<String>>,
    pub intents: Mutex<HashMap<String, Intent>>,
    pub guardrails: Mutex<GuardrailsEngine>,
    pub wallet_address: Mutex<Option<String>>,
    pub intent_sender: mpsc::UnboundedSender<Intent>,
    // NEW fields for query endpoints:
    pub wallet_data: RwLock<WalletDataSnapshot>,  // balance, tokens, history
}

#[derive(Default, Clone, Serialize)]
pub struct WalletDataSnapshot {
    pub sol_balance: Option<f64>,
    pub sol_usd: Option<f64>,
    pub tokens: Vec<TokenSnapshot>,
    pub history: Vec<HistoryEntry>,
    pub prices: HashMap<String, f64>, // mint → USD price
}
```

### Anti-Patterns to Avoid

- **Calling `block_on` in FRB sync functions:** `start_agent_server` MUST be `pub async fn`. FRB v2 runs async on its internal multi-threaded tokio runtime. Calling `Runtime::new().block_on()` inside panics with "cannot start runtime within runtime."
- **Storing revealed API key in Dart state:** The full key is shown ONCE in a dialog. After the dialog closes, Dart holds only the masked version. Never cache the plaintext token in a Riverpod state object that persists.
- **Updating AppState.api_tokens only in AppConfig:** When a key is revoked, BOTH `AppConfig.api_tokens` on disk AND `AppState.api_tokens` Mutex in the running server must be updated. Agents with the revoked token would still succeed if only config is updated.
- **Using `==` for token comparison in new code:** The existing `auth.rs` correctly uses `constant_time_eq`. Any new comparison code must follow the same pattern.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cryptographic random key generation | Timestamp-based or UUID-derived keys | `rand::thread_rng().fill_bytes(&mut buf)` | UUID v4 is not suitable as an API key body; timestamps are predictable |
| Token masking display | Custom string truncation | Single `maskKey()` Dart function (see Pattern 5) | Trivial but must be consistent — one function used everywhere |
| Graceful server shutdown | Custom signal handling | Existing `oneshot::Sender<()>` in `AgentServer` | Already implemented; just call `server.stop()` |
| Port conflict recovery | Retry loop, process scanning | `SO_REUSEADDR` via socket2 | TIME_WAIT is the 99% case; SO_REUSEADDR handles it without complexity |
| Window close interception | Custom native macOS hooks | `window_manager` plugin (already in pubspec) | Plugin handles platform differences correctly |
| Key persistence | Custom file format | `AppConfig.api_tokens` + `config.save()` (0o600 perms already set) | Existing pattern; tokens stored with owner-only file permissions |

**Key insight:** The Rust server-side is ~85% done. The work is the bridge layer, the 5 new query handlers, and the Flutter UI. Resist the urge to rewrite existing Rust server code.

---

## Common Pitfalls

### Pitfall 1: Live Token Revocation Not Propagating to Running Server

**What goes wrong:** User revokes an API key from the UI. The bridge calls `AppConfig.save()` removing the token from disk. But the running `AgentServer` holds `AppState.api_tokens` in a `Mutex<Vec<String>>` that was populated at start time. The revoked token still works until the next restart.

**Why it happens:** Two sources of truth — `AppConfig` on disk and `AppState` in memory. Only one gets updated.

**How to avoid:** When revoking (or creating) a key, the FRB bridge must:
1. Update `AppConfig.api_tokens` and call `config.save()`
2. Also update the live `AppState.api_tokens` Mutex if the server is running

```rust
// In api/agent.rs
pub fn revoke_api_key(token: String) -> Result<(), String> {
    // 1. Update config on disk
    let mut mgr = wallet::manager_pub().write()...;
    mgr.config_mut().api_tokens.retain(|t| t != &token);
    mgr.config_mut().save()...;
    // 2. Update live server state
    if let Ok(guard) = agent_server().lock() {
        if let Some(server) = guard.as_ref() {
            server.state().api_tokens.lock().unwrap().retain(|t| t != &token);
        }
    }
    Ok(())
}
```

**Warning signs:** Revoked token still successfully authenticates immediately after revocation.

### Pitfall 2: Port 9876 Held Across App Restarts (TIME_WAIT)

**What goes wrong:** App is force-quit (Cmd+Q without the window_manager hook firing, or crash). Port 9876 enters TIME_WAIT. Next launch fails to bind with "Address already in use."

**Why it happens:** macOS TCP TIME_WAIT lasts 60–120 seconds. Without `SO_REUSEADDR`, `TcpListener::bind()` fails.

**How to avoid:** Use the socket2 pattern (Pattern 3). Also ensure `window_manager.onWindowClose` is registered to call `stop_agent_server()` gracefully before close.

**Test:** After crash, immediately relaunch. Server must start within 1 second.

### Pitfall 3: Server Start Called from FRB Sync Function

**What goes wrong:** If `start_agent_server` is declared `pub fn` (non-async) and internally tries to call `AgentServer::start(...).await`, the Rust compiler rejects it. Developer might try `Runtime::new().block_on(...)` which panics at runtime inside FRB's tokio context.

**How to avoid:** `start_agent_server` MUST be `pub async fn`. FRB codegen creates a proper Dart `Future<void>` wrapper automatically.

### Pitfall 4: AppConfig Schema Change Breaks Existing Configs

**What goes wrong:** Adding `api_key_entries: Vec<ApiKeyEntry>` to AppConfig without `#[serde(default)]` causes all existing config.json files (without this field) to fail to deserialize with a serde error on launch.

**How to avoid:** Every new field on `AppConfig` MUST have `#[serde(default)]`. Existing fields already follow this pattern (verified in config.rs). New label storage field must follow it too.

### Pitfall 5: Server Toggle Enabled Before Any Key Exists

**What goes wrong:** Server starts but `AppState.api_tokens` is empty. All requests return 401. Server appears to be running but is functionally useless.

**How to avoid:** The UX decision (from CONTEXT.md) already prevents this — server toggle is disabled until at least one key exists. The Riverpod provider enforces this in the UI, and the FRB `start_agent_server` should also return an error if called with an empty token list.

### Pitfall 6: Auto-Start Preference Checked Before Server Is Wired

**What goes wrong:** The SharedPreferences flag `agent_server_enabled` is `true` (from last session). App launches and immediately calls `startAgentServer()` before the wallet is fully loaded, resulting in a server started with no wallet address.

**How to avoid:** Auto-start logic in the `AgentServerNotifier` build method should check both: (1) `agent_server_enabled` pref is true, AND (2) wallet is available (active wallet address is non-null). Use `ref.read(activeWalletProvider)` as a gate.

---

## Code Examples

### Creating a New API Key (Rust bridge)

```rust
// Source: pattern from AppConfig api_tokens field + rand crate
use rand::RngCore;

pub fn create_api_key(label: String) -> Result<String, String> {
    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    let token = format!("db_{}", hex::encode(bytes));

    let mut mgr = wallet::manager_pub().write().map_err(|e| e.to_string())?;
    let config = mgr.config_mut();

    // Soft limit
    if config.api_tokens.len() >= 10 {
        return Err("Maximum of 10 API keys allowed".into());
    }

    config.api_tokens.push(token.clone());
    // Store label separately (see Pattern 5 schema approach)
    config.save().map_err(|e| e.to_string())?;

    // Update live server if running
    if let Ok(guard) = agent_server().lock() {
        if let Some(server) = guard.as_ref() {
            server.state().api_tokens.lock().unwrap().push(token.clone());
        }
    }

    Ok(token) // Returned to Dart ONCE — Dart shows it in dialog, never stores it
}
```

### Query Endpoint Handler Pattern (Rust axum)

```rust
// Source: existing wallet_handler in server.rs as template (axum 0.8)
#[derive(Serialize)]
struct BalanceResponse {
    sol: f64,
    sol_usd: Option<f64>,
    tokens: Vec<TokenBalance>,
}

async fn balance_handler(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let data = state.wallet_data.read().unwrap();
    Json(BalanceResponse {
        sol: data.sol_balance.unwrap_or(0.0),
        sol_usd: data.sol_usd,
        tokens: data.tokens.iter().map(|t| TokenBalance {
            mint: t.mint.clone(),
            amount: t.amount,
            decimals: t.decimals,
            usd_value: t.usd_value,
        }).collect(),
    })
}
```

### AgentServerNotifier (Dart Riverpod)

```dart
// Source: established pattern from api_keys_provider.dart + auth_provider.dart
class AgentServerState {
    final ServerStatus status; // running | stopped | error
    final String? errorMessage;
    final int? port;
    const AgentServerState({
        required this.status,
        this.errorMessage,
        this.port,
    });
}

enum ServerStatus { running, stopped, error }

class AgentServerNotifier extends AsyncNotifier<AgentServerState> {
    static const _prefKey = 'agent_server_enabled';

    @override
    Future<AgentServerState> build() async {
        final prefs = await SharedPreferences.getInstance();
        final wasEnabled = prefs.getBool(_prefKey) ?? false;
        if (wasEnabled) {
            // Auto-start: guard with wallet check
            final address = ref.read(activeWalletProvider);
            if (address != null) {
                return _startServer();
            }
        }
        return const AgentServerState(status: ServerStatus.stopped);
    }
}
```

### NavigationRail Update (app_shell.dart)

```dart
// Add between Contacts and Settings destinations
// Source: existing _destinations list in app_shell.dart
static const _destinations = [
    NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: Text('Dashboard'),
    ),
    NavigationRailDestination(
        icon: Icon(Icons.history_outlined),
        selectedIcon: Icon(Icons.history),
        label: Text('History'),
    ),
    NavigationRailDestination(
        icon: Icon(Icons.contacts_outlined),
        selectedIcon: Icon(Icons.contacts),
        label: Text('Contacts'),
    ),
    // NEW:
    NavigationRailDestination(
        icon: Icon(Icons.lan_outlined),
        selectedIcon: Icon(Icons.lan),
        label: Text('Agent API'),
    ),
    NavigationRailDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: Text('Settings'),
    ),
];

static const _routes = [
    '/dashboard', '/history', '/address-book', '/agent-api', '/settings'
];
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| axum 0.7 path params `/:id` | axum 0.8 path params `/{id}` | Axum 0.8.0, Jan 2025 | server.rs already uses correct syntax — INFR-05 is done |
| FRB 1.x DartSafe / DartOpaque | FRB 2.x StreamSink<T, SseCodec> | FRB 2.0 | Bridge uses modern streaming API; confirmed in Cargo.toml |
| Separate tokio runtime for axum | FRB's built-in multi-thread runtime | FRB 2.x | No separate runtime; use async fn in bridge |

**Already correct:**
- `server.rs` uses `/{id}` curly-brace syntax — INFR-05 is complete, no changes needed
- `auth.rs` uses `constant_time_eq` — INFR-06 was already addressed in Phase 1
- `AgentServer` has `oneshot::Sender<()>` for graceful shutdown — the mechanism exists, just needs wiring to Flutter lifecycle

---

## Open Questions

1. **WalletDataSnapshot freshness — who triggers updates?**
   - What we know: The bridge layer can call `update_agent_server_data()` to push fresh data into AppState
   - What's unclear: Should updates be triggered on a timer, or on demand when the dashboard refreshes, or both?
   - Recommendation: Tie updates to the existing dashboard data refresh cycle. When the Flutter `walletProvider` gets new balance data, also call `update_agent_server_data()`. This keeps data fresh without a separate polling loop. For the `/price?mints=...` endpoint, fetch prices on-demand per request (the endpoint is specifically designed for this).

2. **`/price?mints=...` — fetch from where?**
   - What we know: Helius and Jupiter are both integrated. Jupiter Price API v2 is the standard for token prices on Solana.
   - What's unclear: Should this endpoint make a live Helius/Jupiter HTTP call from within the axum handler (async, fine), or return from the cached snapshot?
   - Recommendation: Live fetch from within the handler via a `reqwest`-style call. The endpoint exists specifically so agents can query prices without getting the full balance. Add `reqwest` to deadbolt_core if not present, or pass a price callback via AppState.

3. **`socket2` explicit vs transitive dependency**
   - What we know: socket2 is present as a transitive dep (via mio/tokio)
   - What's unclear: Whether we can rely on transitive access or need to add it explicitly to Cargo.toml
   - Recommendation: Add `socket2 = "0.5"` explicitly to `deadbolt_core/Cargo.toml`. Relying on transitive deps is fragile — a tokio update could change the socket2 version.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | cargo test (Rust), flutter test (Dart) |
| Config file | None needed — standard cargo test |
| Quick run command | `cd rust && cargo test -p deadbolt_core agent -- --nocapture` |
| Full suite command | `cd rust && cargo test && flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AGNT-01 | Server starts on port 9876 when enabled | unit | `cargo test -p deadbolt_core test_server_start_stop` | ✅ server.rs has test_server_start_stop |
| AGNT-02 | Bearer token auth rejects invalid tokens | unit | `cargo test -p deadbolt_core test_invalid_token_rejected` | ✅ auth.rs has test |
| AGNT-10 | /balance, /tokens, /price, /history return 200 with valid token | integration | `cargo test -p deadbolt_core test_query_endpoints` | ❌ Wave 0 |
| AGNT-11 | API key creation generates db_-prefixed 67-char token | unit | `cargo test -p deadbolt_bridge test_create_api_key` | ❌ Wave 0 |
| AGNT-12 | Revoked key is immediately rejected by running server | unit | `cargo test -p deadbolt_bridge test_revoke_api_key_live` | ❌ Wave 0 |
| AGNT-13 | Curl command contains real bearer token | manual | Visual inspection of curl output in UI | — |
| AGNT-14 | /agent-api route renders without error | widget | `flutter test test/agent_api_screen_test.dart` | ❌ Wave 0 |
| AGNT-15 | Status indicator reflects actual server state | widget | `flutter test test/agent_provider_test.dart` | ❌ Wave 0 |
| INFR-05 | Axum 0.8 route syntax confirmed | code review | `grep -n '{id}' rust/deadbolt_core/src/agent/server.rs` | ✅ already done |
| INFR-08 | Port 9876 free after app close; re-bind succeeds | integration | `cargo test -p deadbolt_core test_port_released_after_stop` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `cd rust && cargo test -p deadbolt_core agent`
- **Per wave merge:** `cd rust && cargo test && flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `rust/deadbolt_core/src/agent/server.rs` — add `test_query_endpoints` covering AGNT-10
- [ ] `rust/deadbolt_bridge/src/api/agent.rs` — add `test_create_api_key` and `test_revoke_api_key_live` covering AGNT-11, AGNT-12
- [ ] `rust/deadbolt_core/src/agent/server.rs` — add `test_port_released_after_stop` for INFR-08
- [ ] `test/agent_api_screen_test.dart` — widget test for AGNT-14
- [ ] `test/agent_provider_test.dart` — provider test for AGNT-15

---

## Sources

### Primary (HIGH confidence)

- Direct codebase inspection: `rust/deadbolt_core/src/agent/server.rs` — AgentServer, existing handlers, axum 0.8 syntax confirmed
- Direct codebase inspection: `rust/deadbolt_bridge/src/api/wallet.rs` — OnceLock<RwLock<>> singleton pattern to follow
- Direct codebase inspection: `rust/deadbolt_core/src/models/config.rs` — AppConfig.api_tokens Vec<String>, 0o600 permissions on save
- Direct codebase inspection: `lib/shared/app_shell.dart` — 4 existing NavigationRail destinations to extend
- Direct codebase inspection: `lib/routing/app_router.dart` — GoRouter ShellRoute to add /agent-api
- Direct codebase inspection: `pubspec.yaml` — window_manager 0.3.9 already present
- `.planning/research/PITFALLS.md` — Port lifecycle, SO_REUSEADDR, Tokio runtime pitfalls
- `.planning/research/ARCHITECTURE.md` — StreamSink pattern, FRB runtime sharing, agent bridge design

### Secondary (MEDIUM confidence)

- flutter_rust_bridge v2 StreamSink docs: https://cjycode.com/flutter_rust_bridge/guides/types/translatable/stream
- axum 0.8 announcement: https://tokio.rs/blog/2025-01-01-announcing-axum-0-8-0
- socket2 crate for SO_REUSEADDR: https://docs.rs/socket2/latest/socket2/

### Tertiary (LOW confidence)

- None — all critical findings verified via codebase inspection or primary docs

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — confirmed in Cargo.toml and pubspec.yaml
- Architecture: HIGH — based on direct inspection of existing wallet.rs pattern
- Pitfalls: HIGH — verified in PITFALLS.md research + codebase confirmation
- Query endpoint data flow: MEDIUM — design recommendation pending final implementation; WalletDataSnapshot approach is sound but /price endpoint live-vs-cached choice is open

**Research date:** 2026-03-16
**Valid until:** 2026-04-16 (stable stack; FRB 2.11.1 is pinned)
