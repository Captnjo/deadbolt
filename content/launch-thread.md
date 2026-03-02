# Deadbolt Launch Thread

## Thread

**1/**
I gave my AI agent a Solana wallet and immediately couldn't sleep.

What if it hallucinated a trade? What if someone prompt-injected it into leaking the private key?

So I built Deadbolt — a signing gateway that sits between the agent and the keys. The agent proposes. I approve.

**2/**
The core idea is simple: your agent should never hold your keys.

Deadbolt runs as a separate service. The agent sends intents — "swap 10 USDC for SOL" — and Deadbolt shows you the full simulated transaction. You approve or reject. The agent never sees the private key.

**3/**
This works even with a hot wallet. The keys live in the Deadbolt app, not in the agent's process. So even if your agent gets prompt-injected or starts hallucinating, it literally cannot sign anything on its own.

Want maximum security? Add a $5 ESP32 hardware signer. Physical button press to approve.

**4/**
But I don't want to babysit every tx. So Deadbolt has configurable guardrails.

Max SOL per tx, daily USD limits, token whitelists, program whitelists, per-agent cooldowns. Intents that break the rules get auto-rejected before they even reach the signing prompt.

**5/**
It's a native macOS SwiftUI app with full DeFi built in:

- Jupiter swaps
- Sanctum liquid staking
- Jito MEV protection
- Transaction simulation + preview before every signature

Plus a REST Intent API so any agent framework can plug in, not just mine.

**6/**
Cloud agents work too. The bridge service lets remote agents connect to your local Deadbolt instance. Your keys stay on your machine. The agent stays in the cloud. They never meet.

**7/**
Deadbolt is open source.

Two signing modes: hot wallet (approve on screen) or hardware wallet (ESP32, physical button press). Both keep keys away from the agent. That's the whole point.

"The lock between your agent and your keys."

Repo link below. Give it a star, open an issue, tell me what's broken.

---

## Standalone Tweet

I built Deadbolt — an open-source signing gateway for agentic DeFi on Solana.

Your AI agent proposes transactions. You approve them. The agent never touches your keys — even in hot wallet mode.

Configurable guardrails (spend limits, token whitelists, rate limiting), tx simulation, Jupiter/Sanctum/Jito, REST API for any agent framework.

---

## Bio / Tagline

**Deadbolt** — The lock between your agent and your keys. Open-source signing gateway for agentic DeFi on Solana.
