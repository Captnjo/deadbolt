# Authentication & Wallet Locking — Design

## Model

Phantom-style: wallet is locked at launch, user authenticates once to unlock. Transactions don't require additional auth. Revealing mnemonic or exporting private key requires re-authentication.

```
App Launch → Lock Screen → Password/Touch ID → Unlocked
                                                   │
                              Auto-lock after N min ◄┘
                                                   │
                              Reveal mnemonic ──► Re-auth
                              Export private key ──► Re-auth
                              Sign transactions ──► No extra auth
```

## Lock Screen

- Deadbolt logo mark + full name (matches title bar style)
- "Unlock Wallet" button centered below
- On tap: password field slides in with Unlock + Cancel buttons
- Touch ID icon alongside password field (if available on device)
- Route: `/lock`

## Auth Requirements

| Operation | Auth Required? |
|-----------|---------------|
| App launch / resume from lock | Yes (password or Touch ID) |
| Sign transactions (swap, send) | No |
| Reveal mnemonic | Yes (re-enter password) |
| Export private key | Yes (re-enter password) |
| Delete wallet | No (confirmation dialog only) |
| Everything else | No |

## Auto-Lock

- Configurable timeout: 5 min, 15 min, 30 min, 1 hour, 4 hours, Never
- Default: 15 minutes of inactivity
- **Inactivity** = no clicks, key presses, or scroll events within the app window. Mouse movement alone does not count.
- When timer fires: navigate to lock screen, Rust `lock_all()` zeroizes seeds from memory
- Settings shows current timeout selection

## Rust Side

### Password Storage
- App password hash stored in `AppConfig` (scrypt-derived, on disk)
- Only the hash is stored, never plaintext
- Salt embedded in hash output (same vault format as existing `vault::encrypt`)

### Bridge Functions (new)
```
set_app_password(password: String) -> Result<(), String>
verify_app_password(password: String) -> Result<bool, String>
has_app_password() -> Result<bool, String>
change_app_password(current: String, new_password: String) -> Result<(), String>
```

### Existing Functions (unchanged)
- `lock_all()` — already zeroizes all seeds from memory
- `unlock_wallet()` — loads seed into SessionManager via Keychain vault key
- `get_mnemonic()` — Flutter gates this behind `verify_app_password` before calling

### No AuthGuard Needed
The existing lock/unlock session mechanism handles auth state. The password is verified at the Flutter layer before calling sensitive bridge functions. The Rust side enforces that seeds are zeroized when locked.

## Flutter Side

### Lock Screen (`lib/features/lock/lock_screen.dart`)
- New route `/lock`
- GoRouter redirect: if wallet is locked → `/lock`
- Logo mark + "DEADBOLT" text
- "Unlock Wallet" button → reveals password field + Unlock/Cancel
- Optional Touch ID button (via `local_auth` package)

### Auth Provider (`lib/providers/auth_provider.dart`)
- Tracks lock/unlock state
- Manages inactivity timer (resets on click, keypress, scroll)
- `lock()` — calls `lock_all_wallets()`, navigates to lock screen
- `unlock(password)` — calls `verify_app_password()`, then `unlock_wallet()` for active wallet
- `autoLockTimeout` — persisted to SharedPreferences

### Inactivity Detection
- Wrap app in `Listener` widget to capture pointer down + key events
- On each qualifying event, reset the timer
- Timer fires → `authProvider.lock()`

### Password Setup
- During onboarding (after wallet creation): "Set a password to protect your wallet"
- Required — no passwordless mode
- Can change password in Settings (requires current password)

### Settings UI
- Preferences section: "Auto-Lock" dropdown (5 min, 15 min, 30 min, 1 hr, 4 hr, Never)
- Security section: "Change Password" button (requires current password)

## Password Flow

### Onboarding
1. User creates/imports wallet
2. Prompt: "Set a password to protect your wallet"
3. Password + confirm password fields
4. `set_app_password()` called
5. Wallet is unlocked, proceed to dashboard

### Unlock
1. Lock screen shown
2. User taps "Unlock Wallet"
3. Password field appears
4. User enters password, taps Unlock
5. `verify_app_password()` → if valid → `unlock_wallet()` for active wallet → navigate to dashboard

### Reveal Mnemonic
1. User navigates to wallet details, taps "Show Recovery Phrase"
2. Password dialog appears (re-enter password)
3. `verify_app_password()` → if valid → `get_mnemonic()` → display words

### Auto-Lock
1. Inactivity timer expires
2. `lock_all_wallets()` called (seeds zeroized)
3. Navigate to `/lock`
