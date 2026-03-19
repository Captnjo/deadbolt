---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: unknown
stopped_at: Completed 04-03-PLAN.md
last_updated: "2026-03-19T05:28:25.801Z"
progress:
  total_phases: 6
  completed_phases: 3
  total_plans: 19
  completed_plans: 18
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-16)

**Core value:** An AI agent can express intent and send transactions to Deadbolt for signing — through hardware wallet or hot wallet — with configurable guardrails the user controls.
**Current focus:** Phase 04 — guardrails-engine

## Current Position

Phase: 04 (guardrails-engine) — EXECUTING
Plan: 2 of 4

## Performance Metrics

**Velocity:**

- Total plans completed: 1
- Average duration: 19 min
- Total execution time: 0.32 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-auth-system | 1 of 5 | 19 min | 19 min |

**Recent Trend:**

- Last 5 plans: 01-01 (19 min)
- Trend: Baseline established

*Updated after each plan completion*
| Phase 01-auth-system P04 | 9 | 2 tasks | 4 files |
| Phase 01-auth-system P03 | 22 | 2 tasks | 6 files |
| Phase 01-auth-system P05 | 3 | 1 tasks | 3 files |
| Phase 02-agent-api-bridge P01 | 3 | 2 tasks | 4 files |
| Phase 02-agent-api-bridge P02 | 7 | 1 tasks | 4 files |
| Phase 02-agent-api-bridge P03 | 3 | 3 tasks | 7 files |
| Phase 02-agent-api-bridge P04 | 5 | 2 tasks | 4 files |
| Phase 03-agent-signing-prompt P01 | 6 | 2 tasks | 5 files |
| Phase 03-agent-signing-prompt P02 | 3 | 2 tasks | 4 files |
| Phase 03-agent-signing-prompt P03 | 4 | 2 tasks | 3 files |
| Phase 03-agent-signing-prompt P05 | 8 | 2 tasks | 7 files |
| Phase 03-agent-signing-prompt P06 | 4 | 2 tasks | 3 files |
| Phase 04-guardrails-engine P01 | 15 | 2 tasks | 7 files |
| Phase 04-guardrails-engine P02 | 2 | 2 tasks | 4 files |
| Phase 04-guardrails-engine P03 | 3 | 2 tasks | 6 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmap: Phase 5 (ESP32) is independent; can run in parallel with Phases 1-4
- Roadmap: INFR-06 (constant-time bearer token) and INFR-07 (zeroization audit) assigned to Phase 1 — security hardening best addressed with the vault/auth work
- Roadmap: INFR-05 (axum 0.8 migration) and INFR-08 (server shutdown) assigned to Phase 2 — belongs with the server exposure work
- [Phase 01-auth-system]: Use Zeroizing::new(plaintext) wrapper so plaintext is auto-zeroed on drop including on error paths
- [Phase 01-auth-system]: constant_time_eq pattern established for all token/secret comparisons in agent API
- [01-01]: 48-byte Keychain entry [16B salt || 32B scrypt-Desktop hash] for app password; avoids separate salt entry
- [01-01]: APP_LOCKED starts true; unlock_app loads Keychain wallets into session then clears lock flag
- [01-01]: FRB bridge scrypt ops are pub async, bool checks are frb(sync) pub fn — prevents Flutter main thread blocking
- [01-01]: Test-specific Keychain accounts (process::id() suffix) isolate tests from real app_password_hash entry
- [Phase 01-auth-system]: [01-04]: password field in OnboardingState uses explicit-null copyWith pattern — clears on any copyWith without it for security, matches error field convention
- [Phase 01-auth-system]: auth.dart created as typed stub (UnimplementedError) rather than modifying generated frb_generated.dart — keeps generated files clean, replaced by codegen when Flutter toolchain available
- [Phase 01-auth-system]: GoRouter lock redirect: watch authProvider in appRouterProvider + hasAppPassword() sync check guards all routes behind /lock when app is locked and password is set
- [Phase 01-auth-system]: showAuthChallengeDialog helper pattern established for gating sensitive operations behind password re-entry from any BuildContext
- [Phase 01-auth-system]: _ChangePasswordDialog co-located in security_settings_section.dart as private ConsumerStatefulWidget — only ever used from SecuritySettingsSection
- [Phase 02-agent-api-bridge]: RwLock (not Mutex) for wallet_data — readers (agent queries) vastly outnumber writers (FRB bridge refresh), allows concurrent reads
- [Phase 02-agent-api-bridge]: api_key_labels is separate HashMap from api_tokens — tokens stay as Vec for backwards compat; labels are opt-in metadata with serde(default)
- [Phase 02-agent-api-bridge]: update_wallet_data() on AgentServer handle (not AppState directly) — consistent with approve/reject_intent pattern
- [Phase 02-agent-api-bridge]: start_agent_server is pub async fn — FRB v2 runs on tokio runtime, async correct, avoids block_on anti-pattern
- [Phase 02-agent-api-bridge]: Deserialize added to WalletDataSnapshot/TokenSnapshot/HistoryEntry in deadbolt_core — required for serde_json::from_str in bridge, no behavioral change to server
- [Phase 02-agent-api-bridge]: _intent_rx dropped for now — Phase 3 will wire to Flutter via StreamSink for signing prompt notifications
- [Phase 02-agent-api-bridge]: AgentServerState uses const named constructors (.stopped(), .running(port), .error(msg)) for clean pattern-matching in UI
- [Phase 02-agent-api-bridge]: Auto-start in build() gates on BOTH agent_server_enabled pref AND activeWalletProvider != null (Pitfall 6 from RESEARCH.md)
- [Phase 02-agent-api-bridge]: [02-03]: WindowListener.onWindowClose calls forceStop() (no pref update) then windowManager.destroy() - preference unchanged so next launch restores auto-start
- [Phase 02-agent-api-bridge]: [02-03]: agent.dart created as typed stub (UnimplementedError) per established auth.dart pattern
- [Phase 02-agent-api-bridge]: Clipboard auto-clear 30s timer implemented proactively in AgentApiScreen as canonical sensitive-copy use case (PLSH-02)
- [Phase 02-agent-api-bridge]: Copy curl command gates on auth challenge to retrieve full token — masked token shown in display only
- [Phase 03-agent-signing-prompt]: stream_intents body stubs sink.add() — SseEncode for IntentEvent generated by FRB codegen; function signature correct, streaming activates after codegen runs
- [Phase 03-agent-signing-prompt]: tokio sync feature added to bridge Cargo.toml — FRB provides runtime but mpsc type requires explicit dep
- [Phase 03-agent-signing-prompt]: crate::frb_generated::StreamSink used in bridge — flutter_rust_bridge::StreamSink removed from root in FRB 2.x
- [Phase 03-agent-signing-prompt]: signMessage stub added to agent.dart (not send.dart) — agent.dart is hand-written stub, send.dart is FRB-generated and must not be modified
- [Phase 03-agent-signing-prompt]: Simulation deferred (SimulationPhase.idle) for SendSol/SendToken — buildUnsignedSendSol/buildUnsignedSendToken don't exist in FRB-generated send.dart; requires future Rust-side unsigned tx builder
- [Phase 03-agent-signing-prompt]: Dynamic NavigationRailDestination list in build() for Badge widget — requires runtime pendingCount via ref.watch
- [Phase 03-agent-signing-prompt]: showSigningPrompt() top-level helper pattern for consistent call site from AppShell auto-show and AgentApiScreen queue Review button
- [Phase 03-agent-signing-prompt]: sign_message placed in sign.rs (not agent.rs) — FRB generates it into stable sign.dart; SignedTxDto reused with empty base64 for message signing
- [Phase 03-agent-signing-prompt]: isSignMessage early-return in approve() skips sendTransaction and pollConfirmation — clean separation of message-signing vs transaction-submission paths
- [Phase 03-agent-signing-prompt]: build_unsigned_legacy mirrors build_sign_legacy without tx.sign() — same instruction pipeline, zeroed signatures for simulateTransaction
- [Phase 03-agent-signing-prompt]: Placeholder blockhash 11111111111111111111111111111111 in unsigned tx — RPC replaces via replaceRecentBlockhash=true so no fresh blockhash needed in Rust
- [04-01]: Swap intents check output_mint (not input_mint) -- whitelist governs tokens you acquire
- [04-01]: Agents CANNOT bypass guardrails -- check() has no bypass parameter, type system enforces this
- [04-01]: GuardrailsConfig.enabled defaults to true via serde(default = 'default_true') for backward compat
- [04-01]: check_token_whitelist is separate from check() to avoid constructing fake Intent for manual txs
- [04-01]: update_guardrails_config does a two-phase update: persist to disk then push to live server engine
- [04-01]: agent_server() changed to pub(crate) -- accessible to sibling bridge modules, not exposed downstream
- [Phase 04-02]: activeThumbColor replaces deprecated activeColor on Switch widget (Flutter 3.31+)
- [Phase 04-02]: Token rows in guardrails whitelist use symbol initial in CircleAvatar — TokenDefinition has no logoUri field
- [Phase 04-guardrails-engine]: SOL sends pass mint=null to checkManualTransaction -- SOL exempt from token whitelist by engine design
- [Phase 04-guardrails-engine]: NFT send flow (NftNotifier) intentionally unmodified -- NFTs exempt from guardrails in v1 per locked decision
- [Phase 04-guardrails-engine]: guardrailBypassed resets on SendState()/SwapState() construction -- one-shot bypass per transaction, not persistent

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 1: Verify actual Flutter SDK version in pubspec.yaml before adopting local_auth 3.x (requires Flutter 3.29+; PROJECT.md says 3.11+)
- Phase 2: Check axum route syntax in existing server.rs (/:id vs /{id}) before assuming 0.8 compatibility
- Phase 4: Decide USD price feed source (Helius, Jupiter price API, or CoinGecko) for dollar-amount guardrail limits before Phase 4 planning
- Phase 5: Verify esp-hal 1.0.0 USB Serial/JTAG under `unstable` feature gate before starting firmware work

## Session Continuity

Last session: 2026-03-19T05:28:25.799Z
Stopped at: Completed 04-03-PLAN.md
Resume file: None
