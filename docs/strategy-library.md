# LITNUP Strategy Library

Complete reference for the 8 reference strategies shipped with the agent runtime. Each strategy is a starting point — operators are expected to extend, fork, or replace them. Code lives at [`agent-runtime/agent_runtime/strategies/`](../agent-runtime/agent_runtime/strategies/).

---

## TL;DR — Which one?

| Strategy | Best in | Worst in | Median Sharpe (testnet) | Code |
|---|---|---|---:|---|
| **MomentumStrategy** | Trending markets | Choppy / sideways | 1.31 | `momentum.py` |
| **MeanReversionStrategy** | Sideways / mean-reverting | Strong trends | 1.12 | `meanrev.py` |
| **BasisTradeStrategy** | Funding-rich periods | Funding compression | 2.41 | `basis.py` |
| **VolCarryStrategy** | Calm markets | Vol-spike regimes | 1.93 | `vol_carry.py` |
| **StatArbStrategy** | All regimes (lower amplitude) | Sudden regime shifts | 1.78 | `stat_arb.py` |
| **FundingArbStrategy** | High-funding-rate periods | Flat funding | 1.65 | `funding_arb.py` |
| **PairsTradeStrategy** | Cointegrated regimes | Cointegration breakdown | 1.45 | `pairs.py` |
| **OptionsCarryStrategy** | Sustained low realized vol | Vol expansions | 1.58 | `options_carry.py` |

**Recommended starter strategies:** Momentum or MeanReversion. Both are simple, well-understood, and don't require external venue integrations to demonstrate. Once your runtime is stable, graduate to BasisTrade for higher Sharpe.

---

## 1. MomentumStrategy — `momentum.py`

### Mechanism
Long when fast SMA crosses above slow SMA. FLAT (close) when fast SMA crosses below. Optional SHORT mode (off by default for regulatory hygiene).

### Parameters
- `fast` — short-window SMA period (default 12)
- `slow` — long-window SMA period (default 48)
- `allow_short` — enable shorts (default `False`)

### When it works
- **Trending markets** — bull runs, bear runs, persistent directional moves
- BTC during major narrative cycles (2020–2021, 2024–2025)

### When it fails
- **Sideways chop** — every cross is a false signal; you eat the spread on every trade
- Sudden regime shifts (the slow SMA hasn't caught up)

### Tuning tips
- Slower windows (24/96) reduce false signals but lag entries
- Add a confirmation threshold: only trade when |fast−slow| > 30 bps to avoid noise
- Pair with a volatility filter: skip signals during high-vol regimes

### Strategy code (canonical)
```python
class MomentumStrategy(Strategy):
    def step(self, price: float) -> Signal:
        if not self.is_warm():
            return Signal("FLAT", 0.0, "warming up")
        fast_sma = self._sma(self.fast)
        slow_sma = self._sma(self.slow)
        spread_bps = (fast_sma - slow_sma) / slow_sma * 10_000
        if fast_sma > slow_sma:
            return Signal("LONG", min(abs(spread_bps)/100.0, 1.0), "...")
        return Signal("FLAT", 0.0, "...")
```

### Recommended for: junior operators learning the framework.

---

## 2. MeanReversionStrategy — `meanrev.py`

### Mechanism
Z-score-based: long when price is `z_entry` standard deviations below the rolling mean. Flat when within band. Optional short above band (off by default).

### Parameters
- `window` — rolling mean/stdev window (default 60)
- `z_entry` — entry threshold in standard deviations (default 1.5)
- `allow_short` — enable shorts (default `False`)

### When it works
- **Sideways / mean-reverting markets** — most of crypto outside major trends
- Pairs that have a clear long-term mean (stablecoin baskets, ETH/BTC ratio in stable periods)

### When it fails
- **Strong directional trends** — keeps buying the dip into a downtrend
- Regime breakouts (the mean shifts; the strategy is left buying yesterday's price)

### Tuning tips
- Shorter window = more reactive, more whipsaws
- z_entry of 2.0 is more conservative; 1.0 is aggressive
- Always pair with a hard stop-loss; mean reversion can become "long the bottom of a crash"

### Recommended for: low-volatility periods, multi-asset portfolios.

---

## 3. BasisTradeStrategy — `basis.py`

### Mechanism
Long spot + short perp when funding rate is rich. Capture the funding spread. Exit when funding compresses.

### Parameters
- `lookback` — funding-rate moving window (default 30 bars)
- `basis_threshold_bps` — minimum carry to enter (default 30 bps)

### When it works
- **Funding-rich periods** — typically when retail is overheated (perps trade above spot)
- Bull markets with lots of long-leverage flow

### When it fails
- **Funding compression** — periods when funding is at or below 0
- Liquidity crunches that push spot/perp prices apart unpredictably

### Real-world implementation notes
- The reference template uses a synthetic funding-rate proxy. **Production: replace `_funding_proxy()` with real funding from Hyperliquid `metaAndAssetCtxs`**.
- Capacity-limited — basis trade size is capped by perp open interest. Don't run >$10M without infrastructure to manage liquidations.
- Best Sharpe of any reference strategy on testnet (2.41 median). Hardest to replicate at scale.

### Recommended for: experienced operators with risk management infrastructure.

---

## 4. VolCarryStrategy — `vol_carry.py`

### Mechanism
Long when realized vol is below threshold. Flat when vol spikes. Profits from premium decay in calm markets.

### Parameters
- `window` — realized-vol calculation window (default 30)
- `vol_threshold_bps` — stay-long ceiling (default 200 bps)
- `vol_spike_bps` — emergency-exit trigger (default 500 bps)

### When it works
- **Calm markets** — sustained low realized vol regimes
- Post-event compression (after a Fed meeting, after a hard fork resolves)

### When it fails
- **Vol expansion regimes** — typically before/during macro events
- Flash crashes (you exit but at the wrong price)

### Tuning tips
- Pair with momentum — if both signals agree, position size aggressively
- Hard stop on vol_spike threshold is non-negotiable
- Realized vol is a lagging indicator; consider implied vol (Deribit) as a filter

### Recommended for: operators with a vol model.

---

## 5. StatArbStrategy — `stat_arb.py`

### Mechanism
EMA-based residual mean reversion. Trades the residual between price and an exponentially-weighted average. Half-life-aware (lower lag than equal-weighted SMA).

### Parameters
- `half_life` — EMA half-life in bars (default 24)
- `z_entry` — entry threshold (default 1.5)
- `z_exit` — close threshold (default 0.5)

### When it works
- **All regimes** (with reduced amplitude) — designed for diversification, not maximum returns
- Higher-frequency settings (1-min, 5-min bars) where simple mean-reversion is too lagged

### When it fails
- **Sudden regime shifts** — EMA recalibrates, but slowly
- Very thin liquidity (residuals don't mean-revert in markets without a true mid-price)

### Tuning tips
- half_life of 24 = ~1 day on hourly bars; tune to your bar frequency
- Add cointegration test: only trade when ADF p-value < 0.05 on residual series
- Volume filter: skip when volume is < 50% of 30-day median

### Recommended for: portfolio diversification slot.

---

## 6. FundingArbStrategy — `funding_arb.py`

### Mechanism
Long when funding is negative (longs receive payments). Currently long-only (so positive-funding shorts go FLAT). In production, with margin support, would short positive-funding markets.

### Parameters
- `window` — funding-rate window (default 8 bars ≈ 8-hour funding cycle)
- `threshold_bps` — entry/exit threshold (default 5 bps)

### When it works
- **High-funding-rate periods** — typically during euphoric long flow
- Multi-venue arb: take the same direction across venues with different funding rates

### When it fails
- **Funding flat or zero** — no edge to capture
- Counter-cyclical with leverage washouts (when shorts get squeezed, funding flips violently)

### Real-world notes
- Reference template uses a return-momentum proxy as funding stub. **Production: pull from Hyperliquid `metaAndAssetCtxs`** or Deribit funding API
- Capacity-limited like basis trade
- Best when combined with basis trade in a portfolio

### Recommended for: cross-venue arb specialists.

---

## 7. PairsTradeStrategy — `pairs.py`

### Mechanism
Trades the residual between an asset and a synthetic reference (or in production, a true second asset like ETH vs BTC × β). Mean-reverts the residual back to the long-run cointegration relationship.

### Parameters
- `window` — rolling residual stdev window (default 60)
- `z_entry` — entry threshold (default 2.0)
- `z_exit` — close threshold (default 0.5)
- `ref_drift` — speed reference adapts to the asset (default 0.0001)

### When it works
- **Cointegrated regimes** — the two assets have a stable long-run relationship
- ETH/BTC during stable correlation periods
- LDO/stETH (where the relationship is fundamentally bounded)

### When it fails
- **Cointegration breakdown** — what you thought was a stable relationship turns out to be coincidence
- Regime shifts that change the fundamental beta between the two assets

### Real-world notes
- Reference template synthesizes a reference price; **production needs a real second-asset feed**
- Run Engle-Granger or Johansen cointegration test daily; pause if p-value > 0.10
- Hedge ratio (β) should be re-estimated weekly

### Recommended for: quant operators with multi-asset infrastructure.

---

## 8. OptionsCarryStrategy — `options_carry.py`

### Mechanism
Implied vs realized vol premium harvest. Long when IV exceeds expected RV (variance risk premium environment). Capacity-limited; long-only template (real strategy would short vol via options).

### Parameters
- `short_window` — RV calculation window (default 20 bars)
- `long_window` — historical baseline (default 90 bars)
- `min_spread_vol_pts` — minimum IV-RV spread to enter (default 1.5 vol points)

### When it works
- **Sustained low realized vol** with IV staying sticky-high
- Periods where the volatility risk premium is wide (typical equity-style behavior)

### When it fails
- **Vol expansions** — RV catches up to IV; you eat the realized
- Regime shifts (a calm period turning volatile mid-trade)

### Real-world notes
- Reference template uses a long-window RV + 1pt premium as fake "implied vol." **Production needs Deribit / Lyra / Premia options data**
- Tail risk is asymmetric — most days you make a little, occasional days you lose a lot. Plan for it.
- Best paired with a tail-risk hedge

### Recommended for: vol-savvy operators with options data infrastructure.

---

## Composing strategies into a portfolio

The 8 strategies above are uncorrelated to varying degrees. Combining them can lift a Sharpe to 2.0+ at the portfolio level even when individual Sharpes are 1.5.

**Suggested low-correlation pairs:**

| Pair | Why it diversifies |
|---|---|
| Momentum + StatArb | One captures trends, one captures reversion |
| BasisTrade + VolCarry | Both are "carry" but in different markets (perp vs spot vol) |
| MeanReversion + FundingArb | One trades price reversal, one trades flow |
| Momentum + OptionsCarry | One is right-tail, one is short-volatility (left-tail) |

**Anti-pattern:**

| Pair | Why it doesn't diversify |
|---|---|
| Momentum + BasisTrade | Both are typically long during the same regimes |
| MeanReversion + StatArb | Highly correlated (both are reversion plays) |
| VolCarry + OptionsCarry | Same fundamental thesis (short vol) |

---

## Adding a custom strategy

```python
from agent_runtime.strategies.base import Strategy, Signal

class MyEdge(Strategy):
    name = "MyEdge"

    def __init__(self, lookback: int = 50):
        super().__init__(lookback=lookback)
        # your state

    def step(self, price: float) -> Signal:
        # 1. Check if we have enough data
        if not self.is_warm():
            return Signal("FLAT", 0.0, "warming up")

        # 2. Compute your indicator
        my_indicator = self._compute_indicator()

        # 3. Decide
        if my_indicator > entry_threshold:
            return Signal("LONG", min(my_indicator / 100, 1.0), "reason here")
        return Signal("FLAT", 0.0, "no signal")

    def _compute_indicator(self) -> float:
        # your logic
        return 0.0
```

Register it in `agent_runtime/strategies/__init__.py`:

```python
from .my_edge import MyEdge

# in build_strategy()
"myedge": MyEdge,
```

Run it:

```bash
python -m agent_runtime.paper_trade --strategy myedge --asset BTC
```

Backtest it:

```bash
python scripts/backtest.py --strategy myedge --asset BTC --days 90
```

---

## Compliance reminder

Every strategy in this library is **paper-only by default**. Putting real money behind any of them requires:

- Personal risk management
- Acceptance that you can lose everything
- Awareness that all examples are educational, not investment advice

The protocol is venue-agnostic. Your strategy is your responsibility. We provide the framework; you ship the alpha.
