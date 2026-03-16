# Pitfalls Research

**Domain:** Solana desktop wallet — agent API, auth/lock, ESP32 BIP39 firmware, transaction guardrails
**Researched:** 2026-03-16
**Confidence:** HIGH (security/crypto domain pitfalls verified against official docs and real CVEs; architecture pitfalls verified against Rust/Flutter ecosystem issues)

---

## Critical Pitfalls

### Pitfall 1: ESP32-C3 RNG Produces Pseudo-Random Entropy Without an Active Entropy Source

**What goes wrong:**
BIP39 mnemonic entropy generated on the ESP32-C3 is cryptographically weak if Wi-Fi, Bluetooth, and the SAR ADC entropy source are all inactive. `esp_random()` silently returns pseudo-random output in this state — there is no error, no warning, and the returned bytes look indistinguishable from true random. A 24-word mnemonic derived from this output may be brute-forceable.

**Why it happens:**
Espressif's official documentation states: "If none of the above conditions are true, the output of the RNG should be considered as pseudo-random only." The ESP32-C3 hardware RNG state is not large enough to sustain a stream of true randomness without continuous replenishment from a hardware entropy source. Developers testing over USB serial (which keeps Wi-Fi/BT off) encounter this silently.

**How to avoid:**
- Explicitly call `bootloader_random_enable()` before collecting entropy for BIP39 generation, then disable it before using ADC/Wi-Fi/BT.
- Alternatively, seed an mbedTLS CTR-DRBG or HMAC-DRBG with hardware RNG bytes, then draw entropy from the DRBG.
- Add a compile-time or runtime assertion that verifies the entropy source is active; fail loudly, not silently.
- Never generate entropy during device initialization before peripherals are configured.

**Warning signs:**
- Firmware generates mnemonics immediately at boot with no peripheral initialization.
- Generated mnemonics pass statistical tests but show low Hamming distance across repeated calls in test harness.
- No `bootloader_random_enable()` call present anywhere in the entropy generation path.

**Phase to address:** ESP32 firmware upgrade phase (BIP39 on-device keygen).

---

### Pitfall 2: NVS Wear Leveling Prevents Secure Erasure of Seed Material

**What goes wrong:**
When a seed phrase or private key is "deleted" from ESP32 NVS flash, the data is not physically erased — wear leveling remaps writes to new sectors, leaving old key material readable in a raw flash dump. An attacker with physical access to the ESP32 can extract the mnemonic even after the user "reset" the device.

**Why it happens:**
NVS wear leveling is a correctness feature (extends flash lifespan), not a security feature. `nvs_erase_key()` marks an entry as free in NVS metadata but does not zero the underlying flash sector. The entry-state bitmap is also written unencrypted, even when NVS encryption is enabled.

**How to avoid:**
- Enable NVS encryption (`nvs_flash_secure_init()`) combined with ESP32 flash encryption — this raises the bar for physical extraction even if sectors are not zeroed.
- For a "factory reset" flow, erase the entire NVS partition (`nvs_flash_erase()`), not individual keys; this forces the controller to map everything fresh.
- Document clearly in the app that "wipe device" erases the NVS partition, and that physical security of the device is the user's responsibility.
- Do not rely on NVS alone; consider encrypting the seed in-firmware with a PIN-derived key before writing to NVS, so raw flash contents are useless without the PIN.

**Warning signs:**
- Firmware deletes individual NVS keys on reset rather than erasing the partition.
- NVS encryption is not configured in `sdkconfig`.
- No flash encryption enabled in production build.

**Phase to address:** ESP32 firmware upgrade phase (BIP39 seed storage).

---

### Pitfall 3: Zeroization of Key Material Is Defeated by Rust Stack Copies

**What goes wrong:**
A seed phrase or private key that implements `Zeroize`/`Drop` still leaves plaintext copies in memory. Every time the value is moved in Rust (returned from a function, passed by value), the compiler copies the bytes to a new stack address. Only the final location is zeroed by `Drop` — earlier copies persist until the stack frame is overwritten by unrelated operations.

**Why it happens:**
Rust's move semantics compile to `memcpy` in the general case. A key struct moved through three function boundaries creates three stack copies; the `Drop` impl zeroes only the one that goes out of scope last. This is not a Rust bug — it is an inherent consequence of value semantics with stack allocation.

**How to avoid:**
- Wrap all key material in `Box<T>` from creation. Heap allocation gives a stable address that does not move; zeroization on drop covers the single location.
- Use the `secrecy` crate (`Secret<Box<[u8]>>`) which prevents re-allocation and mutation of secret data.
- Never pass key material by value across FFI boundaries or to helper functions that take ownership by value; always pass by reference or behind `Box`.
- In the existing Rust vault code, audit every function that touches `SecretKey`, `Seed`, or raw key bytes to confirm they operate on references, not owned values.

**Warning signs:**
- Key structs are `Copy` or returned by value from constructor functions.
- Existing vault code passes `Vec<u8>` containing key bytes rather than `Box<[u8]>` or `SecretVec`.
- `zeroize` is present in `Cargo.toml` but `secrecy` is not.

**Phase to address:** Auth/lock wiring phase (when vault unlock path is exposed to Flutter UI).

---

### Pitfall 4: Port 9876 Already In Use at App Launch — Server Silently Fails or Crashes

**What goes wrong:**
When the Flutter app launches and starts the embedded axum server on `localhost:9876`, the bind fails if another process holds the port (another running Deadbolt instance, a development tool, a prior crashed instance in TIME_WAIT). The failure propagates back through FFI as an error that Flutter UI either swallows or displays as a confusing message. Agents then receive connection refused errors with no explanation.

**Why it happens:**
macOS TCP keeps sockets in TIME_WAIT for 60–120 seconds after close. If the app crashes or is force-quit instead of gracefully shutting down, the port remains occupied. Additionally, any second app instance launched during development will collide immediately.

**How to avoid:**
- Set `SO_REUSEADDR` on the `TcpListener` before binding — this allows binding to TIME_WAIT sockets.
- Perform the bind attempt in Rust; propagate a typed error to Flutter (not a panic) with a clear message: "Port 9876 already in use. Is another instance of Deadbolt running?"
- Display the error in the server status indicator in the Agent API sidebar immediately at launch.
- Consider a fallback: attempt 9876, then 9877, and surface whichever port was bound so agents know where to connect (store in settings).

**Warning signs:**
- Server start is a fire-and-forget FFI call with no return value or error propagation.
- The server status indicator shows "running" even when the bind failed.
- No handling of `AddrInUse` error variant in the axum startup code.

**Phase to address:** Agent API embedded server phase.

---

### Pitfall 5: Tokio Runtime Not Shut Down on App Close — Port Held Across Restarts

**What goes wrong:**
When Flutter closes the desktop window on macOS, the Dart/Flutter engine may not call the Rust cleanup code. The Tokio runtime and its axum server keep running (or the OS forcibly kills the process without triggering `Drop`), leaving port 9876 in TIME_WAIT or still actively bound. The next app launch finds the port occupied.

**Why it happens:**
Flutter desktop's lifecycle channel is not implemented for macOS in the same way as mobile. The `flutter_window_close` package must be used explicitly to intercept the window close event. Without it, the macOS window just closes, and Dart's `main()` returns without any cleanup hook being called into Rust via FFI.

**How to avoid:**
- Use `flutter_window_close` to intercept the close event, call a Rust FFI function to initiate graceful shutdown (send shutdown signal to axum via a `tokio::sync::oneshot` channel), await confirmation, then allow the window to close.
- In the Rust shutdown path, call `Runtime::shutdown_timeout()` with a short timeout (e.g., 2 seconds) to ensure Tokio drops all tasks.
- Test specifically: launch app, kill with Cmd+Q, relaunch immediately — server must start cleanly.

**Warning signs:**
- App has no `flutter_window_close` dependency.
- Rust server module has no shutdown signal mechanism (no `CancellationToken` or `oneshot` channel).
- No integration test that exercises the stop/restart cycle.

**Phase to address:** Agent API embedded server phase.

---

### Pitfall 6: Daily Spend Limit Bypassed via Concurrent Agent Requests

**What goes wrong:**
Two agent requests arrive simultaneously (or in rapid succession). Both check the daily spend tracker, both see remaining budget as sufficient, both pass the guardrail check, and both are signed and submitted — resulting in twice the allowed daily spend. The limit is bypassed entirely without any explicit attack.

**Why it happens:**
Spending limit enforcement typically involves a check-then-act pattern: read the current total, compare to limit, increment if allowed. If the read, compare, and write are not a single atomic critical section, concurrent requests race between the read and the write. Rust's type system prevents data races but does not prevent application-level logic races — a `Mutex` around only the read, or separate locks for read and write, produces this vulnerability.

**How to avoid:**
- Hold a single `Mutex<GuardrailState>` lock for the entire check-and-deduct operation — acquire once, check limit, deduct if allowed, release. Never release and re-acquire between check and deduct.
- Use `AtomicI64` with `compare_exchange` for the running total if lock-free is preferred, but only with a single atomic CAS covering both the check and the increment.
- Write a concurrent test: spawn 10 tokio tasks each submitting a transaction at the limit boundary simultaneously; verify total spend never exceeds limit.

**Warning signs:**
- Existing `guardrails.rs` uses separate `lock()` calls for reading and writing the running total.
- No test for concurrent guardrail evaluation.
- Daily total is stored as a plain `i64` behind an `Arc` without a `Mutex`.

**Phase to address:** Guardrails engine phase.

---

### Pitfall 7: Guardrail State Lost on App Restart — Daily Limit Resets Unintentionally

**What goes wrong:**
The guardrails engine tracks daily spend in memory. When the app is closed and reopened (normal usage pattern — this is a desktop app), the daily total resets to zero. An agent that spent $4,900 of a $5,000 limit before the app was restarted can immediately spend $5,000 more after restart. The "daily limit" is actually a "per-session limit."

**Why it happens:**
In-memory state is the path of least resistance. Persisting guardrail state requires a storage decision (SQLite, flat file, platform keychain) and a reset-at-midnight clock, both of which are non-trivial, so they get deferred.

**How to avoid:**
- Persist the daily spend accumulator to disk (SQLite or a plain JSON file in the app's data directory is sufficient).
- Store the accumulator with the date it belongs to; on load, check if the stored date is today — if not, reset to zero.
- Do this in the guardrails module, not Flutter, so the enforcement is always in Rust regardless of UI state.
- Include the persistence path in phase scope explicitly; do not mark guardrails "done" until persistence is tested across restarts.

**Warning signs:**
- `GuardrailState` struct lives entirely in memory with no serialization impl.
- No date field alongside the daily total.
- No test that simulates an app restart mid-day.

**Phase to address:** Guardrails engine phase.

---

### Pitfall 8: Auth Lock Does Not Gate Concurrent FFI Calls Already In-Flight

**What goes wrong:**
The user's idle timeout fires. Flutter sets the UI state to "locked" and shows the lock screen. Meanwhile, an agent request that arrived 50ms earlier is already in-flight through FFI into the Rust signing path. The signing completes and the transaction is submitted, even though the wallet is now locked from the user's perspective.

**Why it happens:**
The lock state lives in Flutter/Dart. The signing path lives in Rust. If locking is implemented only as a UI gate (don't show the approval prompt when locked), requests that bypass the prompt — such as agent requests that already passed the prompt — can still reach the Rust signer. There is no enforcement at the Rust layer.

**How to avoid:**
- Maintain a `locked: AtomicBool` in the Rust layer (in the same module as the vault). The vault unlock sets it to false; lock/timeout sets it to true.
- Every signing operation in Rust checks `locked` before proceeding and returns `Err(WalletLocked)` if true.
- The FFI boundary enforces lock state independent of Flutter UI state.
- On `WalletLocked` error, the agent receives a `403` with body `{"error": "wallet_locked"}` so it can retry after the user unlocks.

**Warning signs:**
- Lock state is stored only in a Flutter `ValueNotifier` or `BLoC` state.
- Rust signing functions take no auth/lock token parameter.
- There is no `WalletLocked` error variant in the Rust error enum.

**Phase to address:** Auth/lock wiring phase.

---

### Pitfall 9: Agent Approval Queue Lost on App Close — Pending Intents Vanish Silently

**What goes wrong:**
An agent submits five transactions while the app is minimized. The user opens the app, sees one pending approval, approves it, then closes the app before approving the rest. The remaining four intents are dropped. The agent has no way to know whether they were rejected or whether the app closed — it just gets no response. Depending on the agent's retry logic, it either hangs forever or submits duplicate transactions on retry.

**Why it happens:**
The intent queue is maintained in memory in the axum server state. App close drops the state. There is no durable queue and no "rejected on close" response to the waiting agent connections.

**How to avoid:**
- Persist the pending intent queue to SQLite on every state change (add, approve, reject).
- On app startup, load the persisted queue — any intents still in `pending` state that are older than the configured timeout should be automatically rejected with a stored rejection reason.
- When the app closes gracefully, drain the queue: send HTTP `408 Request Timeout` to any still-connected agent polling requests, then persist final state.
- Agent connections should use long-polling with a timeout (e.g., 30 seconds) rather than blocking indefinitely.

**Warning signs:**
- `IntentQueue` is a `Vec<Intent>` inside an `Arc<Mutex<>>` with no persistence.
- App close path does not flush the queue.
- Agent API spec has no defined timeout behavior for pending requests.

**Phase to address:** Agent API + signing prompt phase.

---

### Pitfall 10: Bearer Token Compared With `==` — Timing Attack on Localhost API

**What goes wrong:**
String equality (`==`) short-circuits on the first differing byte. An attacker co-located on the same machine (e.g., a malicious process running as the same user) can enumerate valid API key prefixes by measuring response timing, recovering the token one byte at a time. On localhost, timing differences as small as a few microseconds can be measurable.

**Why it happens:**
`==` on `String` or `&[u8]` is idiomatic Rust for correctness but explicitly wrong for security comparisons. Most developers know about timing attacks for remote servers but dismiss the risk on localhost — incorrectly, since other processes on the same machine can observe timing.

**How to avoid:**
- Use `subtle::ConstantTimeEq` or the `constant_time_eq` crate for bearer token comparison in the axum auth middleware.
- Ensure the stored token is hashed (SHA-256) in the database; compare `hash(presented_token) == stored_hash` with constant-time comparison, not the raw token.
- The Teleport project's PR #2482 demonstrates the exact fix pattern for this in a Rust HTTP server.

**Warning signs:**
- `auth.rs` uses `token == stored_token` or `token.eq(stored_token)`.
- Bearer tokens are stored in plaintext in the database.
- No dependency on `subtle` or `constant_time_eq` in `Cargo.toml`.

**Phase to address:** Agent API auth phase.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| In-memory guardrail state only | No SQLite dependency to add | Daily limits reset on every restart, functionally useless | Never — breaks the security guarantee |
| Lock state enforced only in Flutter UI | Simpler Flutter code | Any Rust FFI call bypasses the lock gate | Never — security enforcement must be in Rust |
| `Vec<u8>` for key material instead of `Box<[u8]>` | Ergonomic, growable | Zeroization is unreliable due to realloc copies | Never for key material — use `SecretVec` from `secrecy` crate |
| Hard-code port 9876 with no error handling | Simple configuration | App cannot launch if port is occupied | MVP only if error is surfaced to user; fix before shipping |
| Skip `bootloader_random_enable()` in ESP32 firmware | Simpler boot sequence | BIP39 entropy may be pseudo-random | Never — entropy quality is non-negotiable |
| Synchronous signing block in Flutter main thread | Simpler call pattern | UI freezes during Rust crypto operations | Never — always use FFI async or isolate |
| Store intent queue only in memory | No SQLite schema needed | Agent requests lost on crash or close | Never for production; acceptable in development only |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| flutter_rust_bridge + axum Tokio runtime | Sharing the FRB Tokio runtime with the axum server | Create a separate, dedicated `tokio::Runtime` for the axum server; FRB manages its own runtime internally |
| ESP32 NVS encryption | Using `nvs_flash_init()` for sensitive data | Use `nvs_flash_secure_init()` with flash encryption enabled in `sdkconfig`; verify at build time |
| ESP32 serial JSON protocol | Assuming serial responses arrive atomically | Serial data arrives in chunks; buffer until newline delimiter, then parse; never parse partial JSON |
| Axum shutdown from Flutter | Calling `Runtime::drop()` from Dart isolate | Send shutdown via `oneshot` channel from Rust FFI call, then await shutdown confirmation before allowing Dart to proceed |
| Solana transaction simulation | Simulating before guardrail check | Simulate after guardrail check passes, not before — simulation fetches blockhash which may expire; keep simulation close to signing |
| Flutter idle timeout | Using `Timer` in UI widget for timeout | Manage timeout in a background service or state management layer that survives widget tree rebuilds; widget-based timers reset on hot reload and navigation |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Blocking Solana RPC call on agent request thread | Agent requests pile up when RPC is slow; UI freezes if FFI is synchronous | All RPC calls must be async inside tokio; never `block_on` inside an axum handler | Every slow RPC call (>200ms) |
| Simulation result cached too long | User sees stale fee estimate; simulated balance differs from actual at signing time | Cap simulation cache at 30 seconds; re-simulate if blockhash is >20 slots old | Any time Solana slot advances significantly |
| ESP32 serial read in tight loop | Host CPU at 100% polling for bytes | Use async serial with `tokio::io` or event-driven read with timeout; never busy-poll | Immediately on any machine with power management |
| SQLite writes on every guardrail check | Agent at high frequency (e.g., 10 req/s) hammers SQLite | Batch writes; only persist when state changes (new request, approval, rejection) — not on reads | Above ~5 agent requests/second |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Binding agent API to `0.0.0.0` instead of `127.0.0.1` | Remote machines on the same network can call the API | Hard-code `127.0.0.1` in the bind address; reject any configuration that changes this in v1 |
| API keys stored in plaintext in SQLite | Leaked database file exposes all keys | Store `sha256(key)` in database; the key is presented only at creation time and never re-read |
| `db_` prefix as sole key validation | Easy to guess or brute-force format | Prefix is for UX only; the key body must be 32+ bytes of CSPRNG output (use `rand::thread_rng()`, not timestamp-based IDs) |
| Logging transaction details at INFO level | Log files in `~/Library/Logs` expose amounts, addresses, and intent contents to any process running as the user | Log only event type and intent ID at INFO; log details only at DEBUG (disabled by default in release builds) |
| Guardrail bypass with password stored in session | Bypass remains active if app is not closed | Bypass must have a hard timeout (e.g., 5 minutes); re-require password after timeout regardless of activity |
| ESP32 pubkey not verified on reconnect | Swapped ESP32 hardware signs without user knowledge | On reconnect, derive expected pubkey from stored identity, compare against device-reported pubkey; reject if mismatch |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Blocking approval prompt — user must act before agent proceeds | App is non-interactive while modal is open; user cannot check balance or history to make an informed decision | Use dismissable overlay (as designed in PROJECT.md); user can navigate away; intent stays in the queue |
| No timeout on pending agent intents | Agent hangs indefinitely waiting for user; agent's retry logic creates duplicate requests | Display countdown timer on each queued intent; auto-reject after configurable timeout (default: 5 minutes) |
| Guardrail error message to user is generic ("transaction rejected") | User cannot diagnose why their agent failed; they have no actionable path | Show specific guardrail message in the approval UI ("daily limit: $4,900/$5,000 used") matching what the agent API returns |
| Lock screen appears mid-transaction simulation | Simulation result is lost; user must restart the flow after unlocking | Simulation runs in Rust, not blocked by UI lock; present result immediately after unlock without re-simulating |
| Auth gate on every sensitive operation with no biometric grace period | Repeated password entry for normal workflows (sign, history, reveal address) is fatiguing | Implement a short grace period (e.g., 30 seconds) after a successful auth before re-challenging; configurable |
| ESP32 mnemonic shown immediately on generation with no backup confirmation | User may not write it down; mnemonic is unrecoverable if lost | Require user to confirm three random words from the phrase before proceeding; clearly label "write this down — you cannot recover it" |

---

## "Looks Done But Isn't" Checklist

- [ ] **Agent API auth:** `auth.rs` exists in Rust — verify it is actually wired into the axum middleware tower stack, not just defined; send an unauthenticated request and confirm `401`.
- [ ] **Guardrails enforcement:** Guardrail code exists — verify it runs on both agent requests AND manual sends (PROJECT.md states this is required); test a manual send that exceeds the per-tx limit.
- [ ] **Vault lock:** Vault module exists — verify that `sign_transaction()` returns `Err(WalletLocked)` when locked; currently the lock state is not wired in Flutter UI at all (PROJECT.md explicitly flags this).
- [ ] **ESP32 entropy:** Firmware generates a key — verify `bootloader_random_enable()` or an active entropy source is present before entropy collection; do not accept generated entropy without this check.
- [ ] **Port bind error handling:** Axum server starts — verify the server status indicator in Flutter shows "failed" (not "running") when bind returns `AddrInUse`; test by binding port 9876 externally before launch.
- [ ] **Daily limit persistence:** Guardrails track spend — verify the daily total survives an app restart; kill and relaunch mid-day and confirm the counter is not reset.
- [ ] **Intent queue persistence:** Intents are accepted — verify that pending intents survive a crash and are re-presented in the queue on next launch; kill -9 the app while an intent is pending.
- [ ] **Serial protocol framing:** ESP32 communication works in testing — verify the Rust serial reader buffers partial JSON correctly; test with a serial terminal that sends the JSON in two chunks.
- [ ] **Shutdown cleanup:** App closes gracefully — verify port 9876 is released and Tokio shuts down; immediately relaunch after Cmd+Q and confirm the server starts cleanly.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Weak ESP32 entropy discovered post-shipping | HIGH | Firmware OTA update required; users must be prompted to regenerate keys with updated firmware; existing keys cannot be retroactively strengthened |
| NVS key material not encrypted (physical extraction possible) | HIGH | Enable flash encryption in a new firmware build; requires factory reset (NVS erase) and key regeneration; cannot encrypt existing unencrypted flash in place |
| Guardrail state not persisted | MEDIUM | Add SQLite schema + migration; backfill is not needed (daily resets are safe as a fresh start); deploy as a patch |
| Port lifecycle not handled (crashes on restart) | LOW | Add `SO_REUSEADDR` to `TcpListener`; add `flutter_window_close` hook; 1–2 day fix |
| Bearer token compared with `==` | MEDIUM | Swap comparison to `constant_time_eq`; re-deploy; no data migration needed; existing tokens remain valid |
| Zeroization bypassed by stack copies | MEDIUM | Audit all key-material structs; migrate from stack-allocated types to `Box<>` / `SecretVec`; regression-test via memory inspection in tests |
| Intent queue lost on crash | MEDIUM | Add SQLite persistence for intent queue; requires schema addition; no data migration needed (in-flight intents at migration time are simply lost once) |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| ESP32 pseudo-random entropy | ESP32 firmware upgrade (BIP39) | Test: attach logic analyzer / print RNG source flag; confirm `bootloader_random_enable()` called; fuzz-test entropy distribution |
| NVS wear leveling exposes seed | ESP32 firmware upgrade (BIP39) | Test: generate key, "delete" from NVS, extract raw flash dump, confirm seed bytes are not readable without flash decryption key |
| Rust stack-copy zeroization leak | Auth/lock wiring phase | Audit: grep for `SecretKey`, `Seed`, `Vec<u8>` in vault code; run `valgrind` or AddressSanitizer on key material lifecycle |
| Port already in use | Agent API embedded server phase | Test: bind port 9876 externally, launch app, confirm status indicator shows failure with actionable message |
| Tokio runtime not shut down on close | Agent API embedded server phase | Test: kill app with Cmd+Q, relaunch immediately — server must start cleanly within 1 second |
| Concurrent requests bypass daily limit | Guardrails engine phase | Test: spawn 20 concurrent HTTP requests at the limit boundary; assert total spend never exceeds limit |
| Guardrail state lost on restart | Guardrails engine phase | Test: accumulate 80% of daily limit, kill app, relaunch, submit one more request — confirm limit is correctly enforced |
| Auth lock does not gate in-flight FFI calls | Auth/lock wiring phase | Test: trigger lock while a signing call is in-flight (use a debug delay in Rust); confirm signing returns `WalletLocked` |
| Agent intent queue lost on close | Agent API + signing prompt phase | Test: kill -9 the app with pending intents; relaunch; confirm intents reappear in queue |
| Bearer token timing attack | Agent API auth phase | Code review: confirm `constant_time_eq` used in `auth.rs`; automated: scan with `cargo audit` |

---

## Sources

- [ESP32-C3 Random Number Generation — ESP-IDF official docs](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c3/api-reference/system/random.html)
- [ESP32 NVS Flash — ESP-IDF official docs](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/storage/nvs_flash.html)
- [A pitfall of Rust's move/copy/drop semantics and zeroing data — benma.github.io](https://benma.github.io/2020/10/16/rust-zeroize-move.html)
- [zeroize crate documentation — docs.rs](https://docs.rs/zeroize/latest/zeroize/)
- [Flutter desktop window close event — flutter_window_close package](https://github.com/zonble/flutter_window_close)
- [Flutter merged threads breaking change — Flutter official docs](https://docs.flutter.dev/release/breaking-changes/macos-windows-merged-threads)
- [flutter_rust_bridge Tokio runtime issue — GitHub #2148](https://github.com/fzyzcjy/flutter_rust_bridge/issues/2148)
- [Axum graceful shutdown example — tokio-rs/axum](https://github.com/tokio-rs/axum/blob/main/examples/graceful-shutdown/src/main.rs)
- [Constant-time bearer token comparison — Teleport PR #2482](https://github.com/gravitational/teleport/pull/2482)
- [TIME_WAIT and port reuse — David Vassallo's blog](https://blog.davidvassallo.me/2010/07/13/time_wait-and-port-reuse/)
- [Race Conditions vs Data Races — Zaid Humayun](https://redixhumayun.github.io/concurrency/2024/05/17/data-race-vs-race-condition.html)
- [Persistence Patterns for AI Agents — DEV Community](https://dev.to/aureus_c_b3ba7f87cc34d74d49/persistence-patterns-for-ai-agents-that-survive-restarts-59ck)
- [Preserving user control in AI agent wallets — a16z crypto](https://a16zcrypto.com/posts/article/preserving-user-control-ai-agents/)

---
*Pitfalls research for: Deadbolt — agent API, auth/lock, ESP32 BIP39, transaction guardrails*
*Researched: 2026-03-16*
