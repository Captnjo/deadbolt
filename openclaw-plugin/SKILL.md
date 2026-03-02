---
name: deadbolt-wallet
description: Control the Deadbolt hardware wallet for Solana — send SOL/tokens, swap via Jupiter, stake via Sanctum, check balances. All transactions require human approval on-device.
metadata:
  openclaw:
    requires:
      env:
        - DEADBOLT_API_TOKEN
      bins:
        - python3
    primaryEnv: DEADBOLT_API_TOKEN
    emoji: "🔐"
---

# Deadbolt Wallet Skill

You can interact with the user's Deadbolt hardware wallet on Solana. Every transaction you submit will require the user to physically approve it — either by clicking "Approve" in the wallet app or pressing the BOOT button on their ESP32 hardware signer.

**Important behavioral rules:**
- You CANNOT sign transactions yourself. You submit intents, and the user approves.
- Always tell the user what you're about to do BEFORE submitting an intent.
- After submitting, tell the user to check their wallet app to approve.
- Poll the status and report back when the transaction is confirmed or rejected.
- Never submit intents the user didn't ask for.
- Amounts for SOL are in **lamports** (1 SOL = 1,000,000,000 lamports).

## Environment

- `DEADBOLT_API_TOKEN` — Bearer token for the wallet API (format: `db_<hex>`)
- `DEADBOLT_API_URL` — API base URL (default: `http://127.0.0.1:9876/api/v1`)

## Available Commands

### Check wallet address
```bash
python3 scripts/wallet.py wallet
```
Returns the active wallet address, source type (hot/hardware), and network.

### Check SOL balance
```bash
python3 scripts/wallet.py balance
```
Returns SOL balance in lamports and display format, USD value, and total portfolio value.

### List token holdings
```bash
python3 scripts/wallet.py tokens
```
Returns all SPL token holdings with mint, symbol, amount, and USD value.

### Get token price
```bash
python3 scripts/wallet.py price <MINT_ADDRESS>
```
Returns the current USD price for a token by its mint address.

Common mints:
- SOL: `So11111111111111111111111111111111111111112`
- USDC: `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v`
- USDT: `Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB`
- jitoSOL: `J1toso1uCk3RLmjorhTtrVwY9HJ7X8V9yYac6Y7kGCPn`
- mSOL: `mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So`
- bSOL: `bSo13r4TkiE4KumL71LsHTPpL2euBYLFx6h9HP3piy1`

### Transaction history
```bash
python3 scripts/wallet.py history [LIMIT]
```
Returns recent transactions. Default limit is 10.

### Send SOL
```bash
python3 scripts/wallet.py send_sol <RECIPIENT> <LAMPORTS> [AGENT_ID] [REASON]
```
Submits a send SOL intent. The user must approve in their wallet app.
Example: Send 0.1 SOL = `python3 scripts/wallet.py send_sol <addr> 100000000 "my-agent" "Sending 0.1 SOL as requested"`

### Send SPL Token
```bash
python3 scripts/wallet.py send_token <RECIPIENT> <MINT> <AMOUNT> [DECIMALS] [AGENT_ID] [REASON]
```
Submits a token transfer intent. Amount is in the token's smallest unit.

### Swap tokens (Jupiter)
```bash
python3 scripts/wallet.py swap <INPUT_MINT> <OUTPUT_MINT> <AMOUNT> [SLIPPAGE_BPS] [AGENT_ID] [REASON]
```
Submits a Jupiter swap intent. Amount is in the input token's smallest unit. Default slippage is 50 bps (0.5%).
Example: Swap 1 SOL to USDC = `python3 scripts/wallet.py swap So11111111111111111111111111111111111111112 EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v 1000000000 50 "dca-bot" "Weekly DCA"`

### Stake SOL (Sanctum)
```bash
python3 scripts/wallet.py stake <LST_MINT> <LAMPORTS> [AGENT_ID] [REASON]
```
Submits a liquid staking intent via Sanctum. Amount is in lamports.
Example: Stake 5 SOL to jitoSOL = `python3 scripts/wallet.py stake J1toso1uCk3RLmjorhTtrVwY9HJ7X8V9yYac6Y7kGCPn 5000000000`

### Check intent status
```bash
python3 scripts/wallet.py status <REQUEST_ID>
```
Polls the status of a submitted intent. Returns status, signature (if confirmed), or error.

### Wait for approval
```bash
python3 scripts/wallet.py wait <REQUEST_ID> [TIMEOUT_SECONDS]
```
Polls status until the intent reaches a terminal state (confirmed/rejected/failed) or times out. Default timeout is 120 seconds. Use this after submitting an intent to wait for the user's response.

## Typical Flow

1. User asks: "Swap 1 SOL to USDC"
2. You check the balance first: `python3 scripts/wallet.py balance`
3. Tell the user: "You have X SOL. I'll submit a swap for 1 SOL to USDC. Please approve in your wallet app."
4. Submit: `python3 scripts/wallet.py swap So111...112 EPjF...t1v 1000000000 50 "openclaw" "Swap 1 SOL to USDC per user request"`
5. Wait: `python3 scripts/wallet.py wait <request_id>`
6. Report result: "Swap confirmed! Signature: 5xYz... You received ~138.5 USDC."

## Error Handling

- If the wallet app isn't running, commands will fail with a connection error. Tell the user to open the Deadbolt app.
- If the token is invalid, you'll get a 401 error. Tell the user to check their API token.
- If an intent is rejected, tell the user and ask if they want to try something else.
- If an intent fails, report the error message from the response.
