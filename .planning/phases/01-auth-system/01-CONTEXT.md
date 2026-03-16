# Phase 1: Auth System - Context

**Gathered:** 2026-03-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire vault unlock and app password gate into Flutter UI with idle auto-lock. The Rust crypto infrastructure (vault encryption, session manager, platform secure storage, wallet manager) is complete — this phase is about building the Flutter auth UI, password management, idle timeout, and wiring the existing FFI bridge calls. Also includes constant-time bearer token comparison (INFR-06) and zeroization audit (INFR-07) as security hardening.

**IMPORTANT SCOPE CLARIFICATION:** The password is app-wide, not wallet-specific. One password unlocks the entire app. All wallets become available after successful authentication.

</domain>

<decisions>
## Implementation Decisions

### Lock Screen UX
- Full branded splash screen on both launch and idle timeout (same screen for both)
- Deadbolt logo + tagline + password field at bottom on dark background
- Brand only — no wallet info visible until unlocked
- Wrong password: shake animation + escalating delay between attempts (1s, 2s, 5s, 10s, 30s...)
- No attempt lockout — just increasingly long delays

### Password Setup Flow
- Password created during onboarding (new step added to existing wizard, before wallet creation)
- Minimum 8 characters with visual strength meter (weak/fair/strong) + confirmation field
- Password hash stored in platform Keychain (macOS Keychain via security-framework, consistent with existing vault key storage)
- No recovery mechanism — if forgotten, user must reset app and re-import wallets from mnemonic
- User can change password from Settings (requires current password first)

### Auth Challenge Behavior
- Password is NOT required for transaction signing — user already clicks Approve in the send/swap flow
- Password IS required for: reveal mnemonic, create/delete API key
- Password IS required to override/bypass guardrails
- Every transaction still shows a confirmation screen (existing behavior) — just no password prompt
- Auth challenge appears as inline dialog (small modal over current screen), not full lock screen
- No grace period — every sensitive operation requires fresh password entry

### Idle Timeout Mechanics
- Default timeout: 15 minutes
- Timeout configurable in Settings
- Activity that resets timer: any mouse movement or key press inside the Deadbolt window
- On lock: Rust zeroizes all seeds from memory (lock_all_wallets), full lock screen shown
- Agent API server stays running while locked — query endpoints respond normally
- Agent signing requests queue up while locked — user reviews queue after unlocking
- Pending queue survives lock/unlock cycle

### Password is App-Wide
- One password unlocks the entire application
- On successful unlock: Rust unlocks ALL wallets (not just active)
- There is no per-wallet password concept
- Hardware wallets don't need password unlock (device-level auth via physical button)

### Claude's Discretion
- Exact lock screen animation/transition
- Password field styling details (show/hide toggle, etc.)
- Strength meter algorithm (zxcvbn or simpler)
- Scrypt parameters for password hashing (can reuse existing vault KDF strength)
- Timer implementation details (WidgetsBindingObserver vs other approach)
- How to handle window focus loss (minimize, switch away) — doesn't reset or trigger lock

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Rust Vault & Session (existing infrastructure to wire)
- `rust/deadbolt_core/src/crypto/vault.rs` — ChaCha20-Poly1305 encryption, scrypt KDF, encrypt/decrypt functions
- `rust/deadbolt_core/src/storage/session.rs` — SessionManager with unlock_with_key, lock, is_unlocked, get_signer
- `rust/deadbolt_core/src/models/wallet_manager.rs` — WalletManager.unlock(), lock_all(), get_active_signer()
- `rust/deadbolt_core/src/storage/keychain.rs` — macOS Keychain storage for vault keys (same pattern for password hash)

### FFI Bridge (functions already exposed to Flutter)
- `rust/deadbolt_bridge/src/api/wallet.rs` — unlock_wallet, lock_wallet, lock_all_wallets, is_wallet_unlocked
- `rust/deadbolt_bridge/src/api/send.rs` — sign_send_sol requires wallet unlocked (get_active_signer fails if locked)

### Flutter (integration points)
- `lib/routing/app_router.dart` — Route guard (currently checks onboarding, needs lock screen check)
- `lib/providers/wallet_provider.dart` — Wallet state management (needs locked/unlocked state)
- `lib/providers/onboarding_provider.dart` — Onboarding wizard (needs password step added)
- `lib/main.dart` — App entry point (needs auth initialization)
- `lib/theme/brand_theme.dart` — Brand colors and styling for lock screen

### Security Fixes (INFR-06, INFR-07)
- `rust/deadbolt_core/src/agent/auth.rs` — Bearer token comparison (needs constant-time fix)
- `rust/deadbolt_core/src/crypto/` — All key material paths need zeroization audit (heap allocation check)

### Research
- `.planning/research/PITFALLS.md` — Zeroization audit details, stack copy concerns
- `.planning/research/ARCHITECTURE.md` — Auth layer design, session token pattern

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `vault.rs` encrypt/decrypt: Full ChaCha20-Poly1305 + scrypt implementation ready to use for password hashing
- `SessionManager`: Already handles in-memory seed storage with zeroize-on-drop
- `WalletManager.unlock()`: Reads vault key from Keychain, decrypts vault, loads seed — full pipeline exists
- `brand_theme.dart`: Solar Flare orange (#F87040), Onyx Black (#000000), all text styles defined
- `onboarding_provider.dart`: Step-based wizard with path branching — password step fits naturally

### Established Patterns
- Riverpod for state management — new auth state should follow same pattern
- GoRouter for navigation — lock screen can be a redirect guard (same pattern as onboarding)
- SharedPreferences for non-sensitive settings — timeout duration can go here
- Keychain via Rust FFI for sensitive data — password hash should use same path

### Integration Points
- `app_router.dart` redirect: Currently `if needsOnboarding → /onboarding`, add `if locked → /lock`
- `wallet_provider.dart`: Add locked/unlocked state tracking
- Onboarding wizard: Add password creation step between welcome and wallet creation
- Settings screen: Add security section with password change and timeout slider
- Send/swap providers: No changes needed (no re-auth on signing)

</code_context>

<specifics>
## Specific Ideas

- Lock screen should feel like Phantom wallet's launch screen — branded but functional
- Escalating delay on wrong password (like iOS incorrect passcode behavior)
- "No recovery" approach is intentional — this is a crypto wallet, security over convenience
- Agent API queue surviving lock is critical for the agent signing use case — agents shouldn't fail just because the user stepped away

</specifics>

<deferred>
## Deferred Ideas

- Touch ID / biometric unlock — v2 (AUTH-V2-01)
- Per-wallet passwords — not planned, app-wide password is the design
- Password recovery via mnemonic — considered and rejected for v1

</deferred>

---

*Phase: 01-auth-system*
*Context gathered: 2026-03-16*
