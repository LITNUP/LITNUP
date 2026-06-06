# LITNUP Agent Runtime

Reference implementation of an autonomous trading agent that integrates with the LITNUP protocol.

This is **the demo that makes the protocol real**. Without it, the contracts are theory. With it, anyone can clone, run, and immediately see an agent paper-trading + producing signed PnL attestations that match what `PerformanceOracle.sol` expects on-chain.

## Architecture

```
┌──────────────────────────────────────────────┐
│            LITNUP Agent                 │
│                                              │
│  ┌────────────┐    ┌──────────────────┐     │
│  │  Strategy  │───▶│  Position Manager│     │
│  │ (momentum, │    │  (paper trader)  │     │
│  │  arb, etc.)│    └────────┬─────────┘     │
│  └─────▲──────┘             │                │
│        │ market data        │ trades         │
│  ┌─────┴──────┐             ▼                │
│  │ Price Feed │     ┌──────────────┐         │
│  │ (Pyth /    │     │  PnL Tracker │         │
│  │  CoinGecko)│     │  + HWM       │         │
│  └────────────┘     └──────┬───────┘         │
│                            │                  │
│                            ▼                  │
│                    ┌────────────────┐         │
│                    │ Oracle Signer  │ ──── EIP-712 signed
│                    │ (eth_account)  │      attestation ─────▶ on-chain
│                    └────────────────┘                          oracle
└──────────────────────────────────────────────┘
```

## Quick start

```bash
# 1. Set up a virtualenv
python -m venv .venv
source .venv/bin/activate    # macOS/Linux
.venv\Scripts\activate        # Windows

# 2. Install
pip install -r requirements.txt

# 3. Generate a fresh signer keypair (for testing)
python scripts/gen_signer.py
# Saves to .env (a private key + address)

# 4. Run the paper trader on testnet config
python -m agent_runtime.paper_trade --strategy momentum --asset BTC --duration 1h

# 5. Sign a sample attestation
python -m agent_runtime.oracle_signer --agent-id 1 --pnl 250 --epoch 1
```

## Files

```
agent-runtime/
├── README.md                      ← you are here
├── requirements.txt
├── .env.example                   ← copy to .env and fill in
├── agent_runtime/
│   ├── __init__.py
│   ├── agent.py                   ← Agent class (orchestrator)
│   ├── price_feed.py              ← CoinGecko / Pyth pulls
│   ├── pnl_tracker.py             ← position + PnL accounting
│   ├── oracle_signer.py           ← EIP-712 attestation signing
│   ├── paper_trade.py             ← live(ish) paper trading loop
│   └── strategies/
│       ├── __init__.py
│       ├── base.py                ← Strategy interface
│       ├── momentum.py            ← simple SMA crossover
│       └── meanrev.py             ← simple z-score mean reversion
├── scripts/
│   ├── gen_signer.py              ← create a signer keypair
│   ├── backtest.py                ← run a strategy on historical data
│   └── verify_attestation.py      ← cross-check a signed attestation
└── tests/
    ├── test_pnl_tracker.py
    └── test_oracle_signer.py
```

## What this proves

When you run `paper_trade.py`, you get:

1. A live strategy making decisions on real market prices
2. A clean PnL log (timestamp, entry, exit, position, return)
3. **EIP-712 signed attestation messages** matching the on-chain `PerformanceOracle.ATTESTATION_TYPEHASH` — these can be sent to a real testnet `PerformanceOracle` contract and they will verify

That last point is the key: **the off-chain signer and the on-chain verifier round-trip cleanly**. Investors and grant reviewers can run this in 5 minutes and see for themselves.

## Disclaimer

This is paper-trading reference code. It does not place real orders. It does not handle live capital. It does not constitute investment advice. Do not run an agent against real funds without thorough audit + insurance.

## Next steps after MVP

- Replace CoinGecko with Pyth on-chain price feeds (real-time, manipulation-resistant)
- Add Hyperliquid live execution (paper → real, opt-in)
- Multi-asset / portfolio-level strategies
- Strategy registry: discover strategies on-chain, run them off-chain
- ZK-proof compute migration (long-term, replaces multi-sig oracle)
