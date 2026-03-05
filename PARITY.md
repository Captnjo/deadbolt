# Swift UI Parity Tracker

Features needed to bring the Flutter app to feature parity with the Swift UI.
Each section is roughly ordered by dependency — earlier items unblock later ones.

**Legend**: `[ ]` = not started, `[~]` = partial, `[x]` = done in Flutter

---

## 1. Dashboard

The main portfolio view — currently a placeholder in Flutter.

- [x] **1.1** SOL balance display (formatted, 9-decimal precision)
- [x] **1.2** SOL → USD conversion (price feed)
- [x] **1.3** Total portfolio USD value
- [x] **1.4** SPL token balances list (mint, amount, USD value)
- [x] **1.5** Staked LST balances section (jitoSOL, mSOL, bSOL, bonkSOL)
- [x] **1.6** NFT gallery grid (thumbnails via Helius, "View All" link)
- [x] **1.7** Quick action toolbar (Send, Receive, Swap buttons)
- [x] **1.8** Secondary actions (Send NFT, Address Book)
- [x] **1.9** Active wallet name + address display with copy
- [x] **1.10** Network badge (DEVNET / MAINNET / TESTNET)
- [x] **1.11** Hardware wallet connection status indicator
- [x] **1.12** Pull-to-refresh / refresh button

---

## 2. Network & RPC Configuration

Required before any on-chain reads or writes.

- [x] **2.1** Solana network picker (Mainnet / Devnet / Testnet)
- [x] **2.2** Helius API key input (secure field + save)
- [x] **2.3** RPC URL display (derived from network + API key)
- [x] **2.4** `getBalance` RPC call for SOL
- [x] **2.5** `getTokenAccountsByOwner` for SPL tokens
- [x] **2.6** Token registry / definitions (symbol, decimals, logo)
- [x] **2.7** Price service (SOL/USD feed)

---

## 3. Receive

- [x] **3.1** QR code generation from active wallet address
- [x] **3.2** Address display (monospaced, selectable)
- [x] **3.3** Copy address button

---

## 4. Send

- [x] **4.1** Recipient address input with Base58 validation
- [x] **4.2** Address book autocomplete / suggestions in recipient field
- [x] **4.3** SOL amount entry with Max button
- [x] **4.4** SPL token selector (dropdown of held tokens)
- [x] **4.5** SPL token amount entry
- [x] **4.6** Transaction building (system transfer / token transfer)
- [x] **4.7** Transaction simulation (`simulateTransaction`)
- [x] **4.8** Fee estimation (base + priority + Jito tip)
- [x] **4.9** Inline review section (amounts, fees, simulation result)
- [x] **4.10** Sign with hot wallet (Keychain signer)
- [x] **4.11** Sign with hardware wallet (ESP32 physical button)
- [~] **4.12** Submit via Jito bundles (mainnet) or standard RPC
- [x] **4.13** Signature confirmation tracking / polling

---

## 5. Swap

- [x] **5.1** Input token selector + amount with Max button
- [x] **5.2** Output token selector
- [x] **5.3** Swap direction toggle (reverse pair)
- [x] **5.4** Jupiter API integration (quote + swap tx)
- [x] **5.5** DFlow API integration (quote + order)
- [x] **5.6** Aggregator toggle (Jupiter / DFlow)
- [x] **5.7** Live debounced quote updates
- [x] **5.8** Route / price impact display (Jupiter)
- [x] **5.9** Jupiter API key configuration in settings
- [x] **5.10** DFlow API key configuration in settings
- [x] **5.11** Review + simulate + submit (same as Send flow)

---

## ~~6. Stake~~ (Removed)

Staking removed — users can swap to LSTs via the Swap screen instead.

---

## 7. Send NFT

- [x] **7.1** Helius `getAssets` integration (fetch NFTs for owner)
- [x] **7.2** NFT selector grid (image + name)
- [x] **7.3** Recipient picker (same as Send)
- [x] **7.4** NFT transfer transaction building
- [x] **7.5** Review + simulate + submit

---

## 8. Transaction History

- [x] **8.1** Fetch transaction list from RPC / Helius
- [x] **8.2** Parse transaction types (Transfer, Swap, Stake, NFT)
- [x] **8.3** Transaction list UI (icon, description, amount, timestamp)
- [x] **8.4** Filter bar (All / Transfer / Swap / Stake / NFT)
- [x] **8.5** Transaction detail view (signature, fees, status, explorer link)
- [x] **8.6** Lazy-loading / pagination
- [x] **8.7** Sidebar navigation entry for History

---

## 9. Address Book

- [x] **9.1** Contact list (tag + address)
- [x] **9.2** Add contact (tag + address with validation)
- [x] **9.3** Edit contact tag
- [x] **9.4** Delete contact (with confirmation)
- [x] **9.5** Search / filter contacts
- [x] **9.6** Copy address from contact
- [x] **9.7** Persist contacts in config
- [x] **9.8** Sidebar navigation entry for Address Book

---

## 10. Authentication & Security

- [ ] **10.1** Auth mode picker (System / App Password / Biometric Only)
- [ ] **10.2** System auth (Touch ID / Face ID via local_auth)
- [ ] **10.3** App password mode (set / change password)
- [ ] **10.4** Biometric-only mode
- [ ] **10.5** Auth gate on sensitive operations (reveal mnemonic, sign tx, delete API key)
- [x] **10.6** Keychain storage for seeds (already in Rust backend)
- [~] **10.7** Wallet lock / unlock (bridge exposed, UI not wired)

---

## 11. Hardware Wallet (macOS)

- [x] **11.1** USB device scanning
- [x] **11.2** Serial connection + handshake (JSON-lines protocol)
- [x] **11.3** Retrieve public key from device
- [ ] **11.4** Generate new keypair on device
- [ ] **11.5** Sign transaction on device (physical button press)
- [ ] **11.6** Auto-detect on app launch (boot modal)
- [ ] **11.7** Connection status in sidebar / dashboard
- [ ] **11.8** Device identity verification (prevent swap)
- [x] **11.9** Hardware wallet settings screen (detect / disconnect)

---

## 12. Agent API & Intent Server

- [ ] **12.1** Embedded HTTP server (localhost, configurable port)
- [ ] **12.2** Bearer token auth (`urg_<hex>`)
- [ ] **12.3** API key management UI (create / revoke / copy)
- [ ] **12.4** Health endpoint (`/api/v1/health`)
- [ ] **12.5** Intent endpoint (receive agent signing requests)
- [ ] **12.6** Agent signing prompt modal (action, balance changes, fees, warnings)
- [ ] **12.7** Approve / reject flow
- [ ] **12.8** Quick test (curl command display + copy)
- [ ] **12.9** Sidebar navigation entry for Agent API
- [ ] **12.10** Server status indicator (running / stopped)

---

## 13. Guardrails

- [ ] **13.1** Per-transaction limits (max SOL, max USD)
- [ ] **13.2** Daily limits (max transactions, max USD)
- [ ] **13.3** Cooldown between transactions
- [ ] **13.4** Token whitelist (allow-list for agent swaps)
- [ ] **13.5** Program whitelist (allow-list for agent interactions)
- [ ] **13.6** Guardrails settings UI
- [ ] **13.7** Live enforcement in agent signing flow

---

## 14. Settings (Full)

- [x] **14.1** Settings screen structure (currently stub with reset button)
- [x] **14.2** Network section (network picker, RPC URL, Helius key)
- [x] **14.3** Swap section (aggregator picker, Jupiter key, DFlow key)
- [x] **14.4** Preferences section (Jito MEV protection toggle)
- [ ] **14.5** Security section (link to auth settings)
- [ ] **14.6** Agent API section (link to guardrails)
- [x] **14.7** Debug: reset onboarding

---

## 15. Wallet Management Enhancements

- [x] **15.1** Create wallet (12-word mnemonic)
- [x] **15.2** Import from seed phrase
- [ ] **15.3** Import from keypair file (JSON 64-byte array)
- [x] **15.4** Multi-wallet list with active selection
- [ ] **15.5** Rename wallet
- [x] **15.6** Show / copy recovery phrase
- [x] **15.7** Delete wallet (with confirmation)
- [x] **15.8** Wallet source labels
- [x] **15.9** Custom emoji assignment per wallet (persisted in SharedPreferences)
- [ ] **15.10** Vanity address generation (prefix grinding)

---

## 16. Navigation Enhancements

- [x] **16.1** Sidebar with Dashboard / History / Settings + wallet avatar at top
- [x] **16.2** Wallet drawer (slide-out panel from avatar for quick wallet switching)
- [x] **16.3** Add Address Book to sidebar
- [ ] **16.4** Add Hardware Wallet to sidebar (macOS only)
- [ ] **16.5** Add Agent API to sidebar (macOS only)

---

## 17. Polish & UX

- [x] **17.1** Dark theme
- [x] **17.2** Onboarding wizard with progress bar
- [x] **17.3** Keyboard shortcuts (Escape for back)
- [ ] **17.4** Cmd+R to refresh dashboard (macOS)
- [x] **17.5** Animated step transitions
- [x] **17.6** Random wallet name generation
- [ ] **17.7** Clipboard auto-clear after 30 seconds (security)
- [ ] **17.8** Empty states for all list screens
- [x] **17.9** Error handling with user-friendly messages

---

## Suggested Build Order

| Priority | Section | Why |
|----------|---------|-----|
| 1 | **2. Network & RPC** | Everything else depends on on-chain data |
| 2 | **1. Dashboard** | Core screen, shows balances |
| 3 | **3. Receive** | Simple, high value — lets users receive funds |
| 4 | **4. Send** | Core transaction flow |
| 5 | **8. Transaction History** | Users need to see what happened |
| 6 | **9. Address Book** | Quality-of-life for Send |
| 7 | **5. Swap** | Major feature, needs API keys |
| 8 | **10. Authentication** | Security hardening |
| 9 | **14. Settings (Full)** | Wraps up configuration |
| 10 | **7. Send NFT** | Nice-to-have |
| 11 | **11. Hardware (remaining)** | TX signing on device |
| 12 | **12. Agent API** | Power user feature |
| 13 | **13. Guardrails** | Agent safety |
| 14 | **15. Wallet Enhancements** | Keypair import, rename, vanity |
| 15 | **16-17. Nav + Polish** | Final touches |
