# Agent Operator Onboarding

> A complete walkthrough from "I want to run an agent" to "my agent is live and earning fees." Plan to take ~2 hours your first time.

This guide assumes you can use a terminal, can write Python, and have a wallet with some $LITNUP.

---

## Step 0 — Decide if you should be an operator

You should run an agent if:
- You have a strategy you've validated outside the protocol (paper-trading + backtest)
- You can dedicate uptime infrastructure (a VPS or even a stable home machine)
- You have at least 10,000 $LITNUP for the bond + a buffer
- You can survive a slashing event without rage-quitting

You should NOT run an agent if:
- You're learning to code as you build it (do that on a paper-only fork first)
- You want passive yield (you should *stake* on someone else's agent)
- You have a strategy that depends on info that won't show up in your attestation (insider edge, off-chain data not in your oracle's view)

---

## Step 1 — Test on testnet first (free)

Don't bond mainnet $LITNUP until your agent has been running profitably (or at least not catastrophically) on Base Sepolia for at least 30 days.

```bash
# 1. Clone the runtime
git clone https://github.com/LITNUP/LITNUP.git
cd LITNUP/agent-runtime

# 2. Install
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# 3. Generate a fresh signer keypair (NOT your main wallet)
python scripts/gen_signer.py

# 4. Run the reference momentum agent on BTC paper-trade
python -m agent_runtime.paper_trade --strategy momentum --asset BTC --duration 24h --interval 60s

# 5. After a day, check the equity curve, drawdown, sharpe, attestation logs
ls logs/
```

You can iterate strategies entirely off-chain. No gas costs. No bond at risk. Learn the system here.

---

## Step 2 — Build (or pick) a strategy

The agent runtime ships with two reference strategies:

| Strategy | When it works | When it fails |
|---|---|---|
| Momentum (SMA cross) | Trending markets | Choppy, sideways markets |
| Mean reversion (z-score) | Sideways, mean-reverting | Strong trends |

These are intentionally simple. You'll do better with:
- Multi-asset portfolio strategies
- Volatility carry / variance risk premium
- Basis trades (perp vs spot)
- Funding rate arbitrage on Hyperliquid
- Cross-DEX arbitrage on Base

To add a custom strategy, subclass `agent_runtime.strategies.base.Strategy`:

```python
from agent_runtime.strategies.base import Strategy, Signal

class MyEdge(Strategy):
    name = "MyEdge"

    def __init__(self):
        super().__init__(lookback=50)
        # your state

    def step(self, price: float) -> Signal:
        if not self.is_warm():
            return Signal("FLAT", 0, "warming")
        # your logic here
        if some_condition:
            return Signal("LONG", 0.8, "reason")
        return Signal("FLAT", 0, "no signal")
```

Backtest it:

```bash
python scripts/backtest.py --strategy myedge --asset BTC --days 180
```

---

## Step 3 — Decide on your fee structure

You set this at enrollment. It's a percentage in basis points.

| Fee % | Implication for stakers | Implication for $LITNUP burn |
|---|---|---|
| 5% | Very competitive; you eat margin | Slow burn rate |
| 10% | Standard; balanced | Moderate burn |
| 15% | Top performers can charge this | Strong burn pressure |
| 25%+ | Only if you're elite or scarce | Very strong burn |

Higher fee = more buyback for $LITNUP = good for the ecosystem. But too high = no stakers. Default suggestion: **start at 10%**, raise once your equity curve is consistently above peers.

---

## Step 4 — Run a stable testnet agent for 30 days

This is the most-skipped, most-important step.

Deploy your strategy. Let it run. Check it daily for the first week, then weekly. You're looking for:
- Does the strategy match your backtest expectations?
- Are attestations being signed without gaps?
- Does the equity curve track your expectations under different market regimes?
- Do you have unhandled error cases (network outages, price feed failures, broken positions)?

Most operators learn the most about their strategy in week 3, when an unanticipated regime shows up.

Mainnet is not a learning environment. Testnet is.

---

## Step 5 — Prepare for mainnet enrollment

### Operations checklist

- [ ] **Hardware**: VPS with 99.9%+ uptime SLA, OR a home machine on UPS with auto-restart. Recommended: $5/mo VPS (DigitalOcean, Hetzner, fly.io).
- [ ] **Hot wallet for the agent controller**: small $LITNUP balance (~100), private key on the production server with chmod 600.
- [ ] **Cold wallet for bond + treasury**: hardware wallet (Ledger). Holds your bond + buffer.
- [ ] **Multisig for high-stakes operations**: optional; recommended if your bond > $10k.
- [ ] **Monitoring**: at least healthcheck.io ping every hour from the agent runtime. Wake-up alert if signals stop.
- [ ] **Logging**: persist all attestations to disk (already done by runtime). Persist all trade decisions.
- [ ] **Backup signer**: a second authorized signer key in case you lose the primary (recoverable via governance).

### Strategy checklist

- [ ] Backtest results across 3+ market regimes (bull, bear, chop)
- [ ] Out-of-sample test on data the strategy hasn't seen
- [ ] Stress test: how does it behave during a -30% market crash?
- [ ] Capital limit: what's the largest stake size where your strategy still works? Set it.
- [ ] Drawdown plan: at what point do you pause vs. ride through?

### Compliance checklist

- [ ] You are NOT a US person, OR you have specific securities counsel approval to operate as such
- [ ] You understand $LITNUP bond is locked + slashable
- [ ] You understand you cannot recover slashed funds
- [ ] You have read and accept the protocol's terms

---

## Step 6 — Enroll on mainnet

> Mainnet is not yet live as of 2026-05-05. Target Q4 2026. The flow below is what you'll execute then.

### Via UI (recommended)

1. Visit `app.litnup.io/operators/enroll`
2. Connect your hardware-wallet-controlled wallet
3. Approve `AgentRegistry` to spend the bond amount
4. Fill in:
   - **Controller address** (the hot signer for your runtime)
   - **Bond amount** (≥10,000 $LITNUP; more is better for staker confidence)
   - **Metadata IPFS CID** (a JSON manifest describing your strategy, code hash, venues; template below)
   - **Protocol fee bps** (e.g. 1000 = 10%)
5. Submit. The contract emits `AgentEnrolled` with your `agentId`.

### Via direct contract call (advanced)

Enrollment is driven by the lifecycle script at `contracts/script/Lifecycle.s.sol` (the only deploy script is `contracts/script/Deploy.s.sol` — there is no separate `EnrollAgent.s.sol`):

```bash
forge script script/Lifecycle.s.sol \
  --rpc-url https://mainnet.base.org \
  --ledger \
  --broadcast \
  --hd-paths "m/44'/60'/0'/0/0"
```

### Metadata manifest template

Pin to IPFS (Pinata, Web3.Storage, or self-host). Example:

```json
{
  "name": "MomentumPro",
  "version": "1.0.0",
  "description": "Multi-asset momentum strategy on Hyperliquid + Aerodrome.",
  "strategy_type": "momentum",
  "venues": ["hyperliquid-perp", "aerodrome-base"],
  "open_source": true,
  "code_hash": "sha256:abc123...",
  "code_url": "https://github.com/myhandle/myagent",
  "operator_contact": "@myhandle (Twitter)",
  "supported_assets": ["BTC", "ETH", "SOL"],
  "expected_drawdown_max": "20%",
  "expected_sharpe": "1.5",
  "version_date": "2026-Q4"
}
```

---

## Step 7 — Run the agent runtime against mainnet

Update `.env`:

```env
ORACLE_SIGNER_PRIVATE_KEY=0x...        # your hot signer key
PERFORMANCE_ORACLE_ADDRESS=0x...       # mainnet oracle
CHAIN_ID=8453                          # Base mainnet
BASE_MAINNET_RPC_URL=https://mainnet.base.org
HYPERLIQUID_LIVE=false                  # keep false until you're really ready
```

Run:

```bash
docker-compose -f deploy/docker-compose.yml up -d
docker-compose logs -f
```

The container has hard CPU + RAM caps and a read-only filesystem (writes only to `./logs`). It auto-restarts on crash.

---

## Step 8 — Monitor

Daily for the first week. Then weekly. Check:

- **Attestations being signed** (every 4 hours; gaps indicate a runtime issue)
- **Equity curve** (vs. expected from backtest)
- **Drawdown** (proximity to slashing threshold)
- **Stake flow** (incoming/outgoing — if all stakers leave, time to investigate why)
- **Network/venue health** (Base, Hyperliquid uptime)

Dashboards / metrics: `app.litnup.io/operators/<your-agent-id>`.

---

## Step 9 — Get and respond to feedback

Stakers will tell you, by their actions, what's working. If your stake is shrinking, ask why. Honest answer: probably because:
- Your strategy is underperforming
- You're not communicating in public
- There's a competitor agent with better numbers

The strategies that thrive are the ones whose operators *talk* publicly about wins, losses, and adjustments. Build trust beyond the numbers.

---

## Step 10 — Iterate or retire

Strategies decay. The best operators rotate strategies on a quarterly cadence — same agent, evolved logic.

When you're ready to retire:
1. Pause the agent (oracle stops attesting once you signal)
2. Wait 7 days for stakers to unstake
3. Call `withdrawInit()`; wait 14 days
4. Call `withdrawComplete()` to reclaim your bond

Your `agentId` remains in the registry as a historical record — your track record persists, regardless of whether you're still active.

---

## Common pitfalls

- **Running mainnet on a laptop that sleeps.** Your agent stops, your stakers feel the gap, slashing risk rises. Use a server.
- **No drawdown plan.** When the inevitable bad week hits, you'll panic-deleverage. Plan now.
- **Ignoring your stakers.** They are your silent partners. Treat them like real LPs.
- **Single point of failure on the signer key.** Lose it, lose your agent. Backup signers. Hardware wallets.
- **Trading too large.** Slippage compounds. The protocol caps each vault, but you should self-cap below that for your strategy's capacity.
- **Premature mainnet.** 30 days of testnet minimum. We mean it.
