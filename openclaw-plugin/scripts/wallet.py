#!/usr/bin/env python3
"""Deadbolt Wallet CLI — used by OpenClaw skill to interact with the Intent API."""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.request
import urllib.error
from typing import Optional

BASE_URL = os.environ.get("DEADBOLT_API_URL", "http://127.0.0.1:9876/api/v1")
TOKEN = os.environ.get("DEADBOLT_API_TOKEN", "")


def _request(method: str, path: str, body: dict | None = None) -> dict | list:
    """Make an authenticated HTTP request to the Deadbolt API."""
    url = f"{BASE_URL}/{path}"
    data = json.dumps(body).encode() if body else None
    headers = {"Authorization": f"Bearer {TOKEN}"}
    if data:
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        try:
            err = json.loads(error_body)
            print(f"Error {e.code}: {err.get('error', error_body)}", file=sys.stderr)
        except json.JSONDecodeError:
            print(f"Error {e.code}: {error_body}", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"Connection error: {e.reason}", file=sys.stderr)
        print("Is the Deadbolt wallet app running?", file=sys.stderr)
        sys.exit(1)


def _get(path: str) -> dict | list:
    return _request("GET", path)


def _post(path: str, body: dict) -> dict:
    return _request("POST", path, body)


def cmd_wallet():
    """Get active wallet info."""
    data = _get("wallet")
    print(json.dumps(data, indent=2))


def cmd_balance():
    """Get SOL balance."""
    data = _get("balance")
    print(json.dumps(data, indent=2))


def cmd_tokens():
    """List token holdings."""
    data = _get("tokens")
    print(json.dumps(data, indent=2))


def cmd_price(mint: str):
    """Get token price."""
    data = _get(f"price?mint={mint}")
    print(json.dumps(data, indent=2))


def cmd_history(limit: int = 10):
    """Get recent transactions."""
    data = _get(f"history?limit={limit}")
    print(json.dumps(data, indent=2))


def cmd_status(request_id: str):
    """Check intent status."""
    data = _get(f"status/{request_id}")
    print(json.dumps(data, indent=2))


def cmd_send_sol(recipient: str, amount: int, agent_id: str = "openclaw", reason: str = ""):
    """Submit a send SOL intent."""
    body = {
        "type": "send_sol",
        "params": {"recipient": recipient, "amount": amount},
        "metadata": {"agent_id": agent_id, "reason": reason or f"Send {amount} lamports to {recipient}"},
    }
    data = _post("intent", body)
    print(json.dumps(data, indent=2))


def cmd_send_token(
    recipient: str, mint: str, amount: int, decimals: int | None = None,
    agent_id: str = "openclaw", reason: str = "",
):
    """Submit a send token intent."""
    params: dict = {"recipient": recipient, "mint": mint, "amount": amount}
    if decimals is not None:
        params["decimals"] = decimals
    body = {
        "type": "send_token",
        "params": params,
        "metadata": {"agent_id": agent_id, "reason": reason or f"Send token {mint[:8]}... to {recipient[:8]}..."},
    }
    data = _post("intent", body)
    print(json.dumps(data, indent=2))


def cmd_swap(
    input_mint: str, output_mint: str, amount: int, slippage_bps: int = 50,
    agent_id: str = "openclaw", reason: str = "",
):
    """Submit a Jupiter swap intent."""
    body = {
        "type": "swap",
        "params": {
            "input_mint": input_mint,
            "output_mint": output_mint,
            "amount": amount,
            "slippage_bps": slippage_bps,
        },
        "metadata": {"agent_id": agent_id, "reason": reason or f"Swap {input_mint[:8]}... -> {output_mint[:8]}..."},
    }
    data = _post("intent", body)
    print(json.dumps(data, indent=2))


def cmd_stake(lst_mint: str, amount: int, agent_id: str = "openclaw", reason: str = ""):
    """Submit a Sanctum staking intent."""
    body = {
        "type": "stake",
        "params": {"lst_mint": lst_mint, "amount": amount},
        "metadata": {"agent_id": agent_id, "reason": reason or f"Stake {amount} lamports -> {lst_mint[:8]}..."},
    }
    data = _post("intent", body)
    print(json.dumps(data, indent=2))


def cmd_wait(request_id: str, timeout: int = 120):
    """Poll until intent reaches a terminal state."""
    terminal = {"confirmed", "rejected", "failed"}
    start = time.time()
    last_status = ""

    while time.time() - start < timeout:
        data = _get(f"status/{request_id}")
        status = data.get("status", "")

        if status != last_status:
            last_status = status
            if status in terminal:
                print(json.dumps(data, indent=2))
                return
            print(f"Status: {status}...", file=sys.stderr)

        time.sleep(2)

    print(f"Timeout after {timeout}s. Last status: {last_status}", file=sys.stderr)
    data = _get(f"status/{request_id}")
    print(json.dumps(data, indent=2))


def main():
    if not TOKEN:
        print("Error: DEADBOLT_API_TOKEN not set", file=sys.stderr)
        sys.exit(1)

    if len(sys.argv) < 2:
        print("Usage: wallet.py <command> [args...]", file=sys.stderr)
        print("Commands: wallet, balance, tokens, price, history, status,", file=sys.stderr)
        print("          send_sol, send_token, swap, stake, wait", file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "wallet":
        cmd_wallet()
    elif cmd == "balance":
        cmd_balance()
    elif cmd == "tokens":
        cmd_tokens()
    elif cmd == "price":
        if len(sys.argv) < 3:
            print("Usage: wallet.py price <MINT>", file=sys.stderr)
            sys.exit(1)
        cmd_price(sys.argv[2])
    elif cmd == "history":
        limit = int(sys.argv[2]) if len(sys.argv) > 2 else 10
        cmd_history(limit)
    elif cmd == "status":
        if len(sys.argv) < 3:
            print("Usage: wallet.py status <REQUEST_ID>", file=sys.stderr)
            sys.exit(1)
        cmd_status(sys.argv[2])
    elif cmd == "send_sol":
        if len(sys.argv) < 4:
            print("Usage: wallet.py send_sol <RECIPIENT> <LAMPORTS> [AGENT_ID] [REASON]", file=sys.stderr)
            sys.exit(1)
        cmd_send_sol(
            sys.argv[2], int(sys.argv[3]),
            sys.argv[4] if len(sys.argv) > 4 else "openclaw",
            sys.argv[5] if len(sys.argv) > 5 else "",
        )
    elif cmd == "send_token":
        if len(sys.argv) < 5:
            print("Usage: wallet.py send_token <RECIPIENT> <MINT> <AMOUNT> [DECIMALS] [AGENT_ID] [REASON]", file=sys.stderr)
            sys.exit(1)
        cmd_send_token(
            sys.argv[2], sys.argv[3], int(sys.argv[4]),
            int(sys.argv[5]) if len(sys.argv) > 5 else None,
            sys.argv[6] if len(sys.argv) > 6 else "openclaw",
            sys.argv[7] if len(sys.argv) > 7 else "",
        )
    elif cmd == "swap":
        if len(sys.argv) < 5:
            print("Usage: wallet.py swap <INPUT_MINT> <OUTPUT_MINT> <AMOUNT> [SLIPPAGE_BPS] [AGENT_ID] [REASON]", file=sys.stderr)
            sys.exit(1)
        cmd_swap(
            sys.argv[2], sys.argv[3], int(sys.argv[4]),
            int(sys.argv[5]) if len(sys.argv) > 5 else 50,
            sys.argv[6] if len(sys.argv) > 6 else "openclaw",
            sys.argv[7] if len(sys.argv) > 7 else "",
        )
    elif cmd == "stake":
        if len(sys.argv) < 4:
            print("Usage: wallet.py stake <LST_MINT> <LAMPORTS> [AGENT_ID] [REASON]", file=sys.stderr)
            sys.exit(1)
        cmd_stake(
            sys.argv[2], int(sys.argv[3]),
            sys.argv[4] if len(sys.argv) > 4 else "openclaw",
            sys.argv[5] if len(sys.argv) > 5 else "",
        )
    elif cmd == "wait":
        if len(sys.argv) < 3:
            print("Usage: wallet.py wait <REQUEST_ID> [TIMEOUT]", file=sys.stderr)
            sys.exit(1)
        cmd_wait(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 120)
    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
