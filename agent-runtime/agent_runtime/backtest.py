"""Backtest harness for LITNUP strategies.

Replays historical price data through any Strategy implementation and reports:
  - Equity curve
  - Total return
  - Max drawdown
  - Sharpe ratio
  - Win rate
  - Per-trade PnL distribution
  - Slashing events (under LITNUP's 25%/10%/1-cycle rules)

Usage (programmatic):
    from agent_runtime.backtest import run_backtest
    from agent_runtime.strategies.momentum import MomentumStrategy

    result = run_backtest(
        strategy=MomentumStrategy(fast=12, slow=48),
        prices_csv="data/btc-1h-2024.csv",
        initial_equity=10_000.0,
        attestation_interval_secs=4 * 3600,
    )
    print(result.summary())

Usage (CLI):
    alphagentic-cli backtest --strategy momentum --asset BTC \
        --start 2024-01-01 --end 2024-12-31 --initial-equity 10000

CSV format expected:
    timestamp,price
    1704067200,42234.50
    1704070800,42301.20
    ...

If no CSV is provided, the harness generates a synthetic GBM-like price series
for smoke-testing. Real backtests need real data — pull from Coinbase, Hyperliquid,
or your own oracle archive.
"""
from __future__ import annotations

import csv
import json
import math
import random
import time
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional

from .strategies.base import Strategy, Signal


# ============================================================
# CONFIGURATION
# ============================================================

# Protocol-aligned slashing rules — keep in sync with StakingVault.sol
DRAWDOWN_THRESHOLD = 0.25     # 25% drawdown triggers slash
SLASH_FRACTION    = 0.10      # 10% of vault slashed
SLASH_CONFIRM_CYC = 1         # # of consecutive attestation cycles in breach

# Default fees
DEFAULT_FEE_BPS    = 200      # 2% protocol fee on positive PnL


# ============================================================
# RESULT TYPES
# ============================================================

@dataclass
class Trade:
    side: str
    entry_ts: int
    exit_ts: int
    entry_price: float
    exit_price: float
    size_usd: float
    pnl: float

    @property
    def return_pct(self) -> float:
        return (self.pnl / self.size_usd) if self.size_usd else 0.0


@dataclass
class SlashEvent:
    ts: int
    drawdown_pct: float
    slash_amount_usd: float


@dataclass
class BacktestResult:
    strategy_name: str
    asset: str
    period_start: int
    period_end: int
    initial_equity: float
    final_equity: float
    trades: list[Trade] = field(default_factory=list)
    slash_events: list[SlashEvent] = field(default_factory=list)
    equity_curve: list[tuple[int, float]] = field(default_factory=list)

    @property
    def total_return_pct(self) -> float:
        return (self.final_equity / self.initial_equity - 1.0) * 100

    @property
    def max_drawdown_pct(self) -> float:
        if not self.equity_curve:
            return 0.0
        peak = self.equity_curve[0][1]
        max_dd = 0.0
        for _, eq in self.equity_curve:
            if eq > peak:
                peak = eq
            dd = 1.0 - eq / peak if peak > 0 else 0.0
            if dd > max_dd:
                max_dd = dd
        return max_dd * 100

    @property
    def win_rate_pct(self) -> float:
        if not self.trades:
            return 0.0
        wins = sum(1 for t in self.trades if t.pnl > 0)
        return wins / len(self.trades) * 100

    @property
    def sharpe(self) -> float:
        """Annualized Sharpe using trade-by-trade returns."""
        if len(self.trades) < 2:
            return 0.0
        returns = [t.return_pct for t in self.trades]
        mean = sum(returns) / len(returns)
        var = sum((r - mean) ** 2 for r in returns) / (len(returns) - 1)
        sd = math.sqrt(var)
        if sd == 0:
            return 0.0
        # Annualize assuming ~252 effective trade-cycles/year
        return (mean / sd) * math.sqrt(252)

    @property
    def slashed(self) -> bool:
        return len(self.slash_events) > 0

    def summary(self) -> dict:
        return {
            "strategy":         self.strategy_name,
            "asset":            self.asset,
            "period":           f"{self.period_start} → {self.period_end}",
            "initial_equity":   self.initial_equity,
            "final_equity":     round(self.final_equity, 2),
            "total_return_pct": round(self.total_return_pct, 2),
            "max_drawdown_pct": round(self.max_drawdown_pct, 2),
            "trade_count":      len(self.trades),
            "win_rate_pct":     round(self.win_rate_pct, 2),
            "sharpe":           round(self.sharpe, 2),
            "slash_events":     len(self.slash_events),
            "would_be_slashed": self.slashed,
        }


# ============================================================
# CORE BACKTEST LOOP
# ============================================================

def run_backtest(
    strategy: Strategy,
    prices: Optional[list[tuple[int, float]]] = None,
    prices_csv: Optional[str | Path] = None,
    asset: str = "BTC",
    initial_equity: float = 10_000.0,
    fee_bps: int = DEFAULT_FEE_BPS,
    attestation_interval_secs: int = 4 * 3600,
    position_size_pct: float = 1.0,  # use 100% of equity per trade
) -> BacktestResult:
    """Run a backtest. Returns a BacktestResult."""

    if prices is None:
        if prices_csv is not None:
            prices = _load_csv(prices_csv)
        else:
            prices = _synthetic_gbm()

    if not prices:
        raise ValueError("no prices provided and synthetic generation failed")

    result = BacktestResult(
        strategy_name=strategy.name,
        asset=asset,
        period_start=prices[0][0],
        period_end=prices[-1][0],
        initial_equity=initial_equity,
        final_equity=initial_equity,
    )

    equity = initial_equity
    peak_equity = initial_equity

    # Currently-open position
    open_side: Optional[str] = None     # "LONG" / "SHORT"
    entry_price: float = 0.0
    entry_ts: int = 0
    size_usd: float = 0.0

    # Attestation cycle tracker (slashing simulation)
    cycles_in_breach = 0
    last_attestation_ts = prices[0][0]
    attestation_equity = initial_equity   # equity at last attestation
    attestation_peak = initial_equity     # peak equity ever recorded

    for ts, price in prices:
        strategy.feed(price)
        if not strategy.is_warm():
            result.equity_curve.append((ts, equity))
            continue

        signal = strategy.step(price)

        # Compute unrealized PnL if a position is open
        unrealized = 0.0
        if open_side == "LONG":
            unrealized = (price - entry_price) / entry_price * size_usd
        elif open_side == "SHORT":
            unrealized = (entry_price - price) / entry_price * size_usd

        mark_equity = equity + unrealized

        # ============================================================
        # Trade transitions
        # ============================================================
        if signal.kind == "FLAT" and open_side is not None:
            # close
            pnl = unrealized
            fee = max(0.0, pnl) * (fee_bps / 10_000)
            net = pnl - fee
            equity += net
            trade = Trade(
                side=open_side, entry_ts=entry_ts, exit_ts=ts,
                entry_price=entry_price, exit_price=price,
                size_usd=size_usd, pnl=net,
            )
            result.trades.append(trade)
            open_side = None
            entry_price = 0.0
            size_usd = 0.0
            mark_equity = equity

        elif signal.kind in ("LONG", "SHORT"):
            if open_side != signal.kind:
                # close existing if opposite
                if open_side is not None:
                    pnl = unrealized
                    fee = max(0.0, pnl) * (fee_bps / 10_000)
                    net = pnl - fee
                    equity += net
                    result.trades.append(Trade(
                        side=open_side, entry_ts=entry_ts, exit_ts=ts,
                        entry_price=entry_price, exit_price=price,
                        size_usd=size_usd, pnl=net,
                    ))
                # open new
                open_side = signal.kind
                entry_price = price
                entry_ts = ts
                size_usd = equity * position_size_pct * signal.target_size

        # ============================================================
        # Equity curve + drawdown tracking
        # ============================================================
        if mark_equity > attestation_peak:
            attestation_peak = mark_equity
        result.equity_curve.append((ts, mark_equity))

        # ============================================================
        # Attestation-cycle slashing simulation
        # ============================================================
        if ts - last_attestation_ts >= attestation_interval_secs:
            # Snapshot equity at attestation tick
            dd = 1.0 - mark_equity / attestation_peak if attestation_peak > 0 else 0.0
            if dd >= DRAWDOWN_THRESHOLD:
                cycles_in_breach += 1
                if cycles_in_breach >= SLASH_CONFIRM_CYC:
                    slash_amt = mark_equity * SLASH_FRACTION
                    equity -= slash_amt
                    if open_side is not None:
                        size_usd *= (1 - SLASH_FRACTION)
                    result.slash_events.append(SlashEvent(
                        ts=ts, drawdown_pct=dd * 100, slash_amount_usd=slash_amt,
                    ))
                    cycles_in_breach = 0
                    attestation_peak = equity   # reset after slash
            else:
                cycles_in_breach = 0
            last_attestation_ts = ts

    # Close any final open position at last price
    if open_side is not None:
        last_ts, last_price = prices[-1]
        pnl = 0.0
        if open_side == "LONG":
            pnl = (last_price - entry_price) / entry_price * size_usd
        else:
            pnl = (entry_price - last_price) / entry_price * size_usd
        fee = max(0.0, pnl) * (fee_bps / 10_000)
        equity += pnl - fee
        result.trades.append(Trade(
            side=open_side, entry_ts=entry_ts, exit_ts=last_ts,
            entry_price=entry_price, exit_price=last_price,
            size_usd=size_usd, pnl=pnl - fee,
        ))

    result.final_equity = equity
    return result


# ============================================================
# CSV LOADING + SYNTHETIC GENERATION
# ============================================================

def _load_csv(path: str | Path) -> list[tuple[int, float]]:
    out: list[tuple[int, float]] = []
    with open(path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Allow various column names
            ts_key = next((k for k in ("timestamp", "ts", "time") if k in row), None)
            px_key = next((k for k in ("price", "close", "px") if k in row), None)
            if not ts_key or not px_key:
                continue
            try:
                ts = int(float(row[ts_key]))
                px = float(row[px_key])
                out.append((ts, px))
            except (ValueError, TypeError):
                continue
    out.sort()
    return out


def _synthetic_gbm(
    n_ticks: int = 1000,
    start_price: float = 50_000.0,
    annualized_drift: float = 0.05,
    annualized_vol: float = 0.6,
    tick_secs: int = 3600,
    seed: int = 42,
) -> list[tuple[int, float]]:
    """Generate a synthetic geometric-Brownian-motion price series for smoke-testing."""
    rng = random.Random(seed)
    dt = tick_secs / (365 * 24 * 3600)   # fraction of a year per tick
    mu = annualized_drift
    sigma = annualized_vol

    out: list[tuple[int, float]] = []
    px = start_price
    t = int(time.time() - n_ticks * tick_secs)
    for _ in range(n_ticks):
        # GBM increment
        z = rng.gauss(0, 1)
        px *= math.exp((mu - 0.5 * sigma ** 2) * dt + sigma * math.sqrt(dt) * z)
        out.append((t, round(px, 2)))
        t += tick_secs
    return out


# ============================================================
# REPORT SERIALIZATION
# ============================================================

def write_report(result: BacktestResult, output_dir: str | Path) -> Path:
    """Write a JSON report + CSV equity curve to `output_dir`. Returns the JSON path."""
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)
    stamp = int(time.time())
    json_path = out / f"backtest-{result.strategy_name.lower()}-{result.asset.lower()}-{stamp}.json"
    csv_path = out / f"equity-{result.strategy_name.lower()}-{result.asset.lower()}-{stamp}.csv"

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump({
            "summary": result.summary(),
            "trades": [asdict(t) for t in result.trades],
            "slash_events": [asdict(s) for s in result.slash_events],
        }, f, indent=2)

    with open(csv_path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["timestamp", "equity"])
        for ts, eq in result.equity_curve:
            w.writerow([ts, round(eq, 4)])

    return json_path


# ============================================================
# CLI ENTRYPOINT (used by alphagentic-cli backtest)
# ============================================================

def cli_run(strategy_name: str, asset: str, start: str, end: str,
            initial_equity: float = 10_000.0, prices_csv: Optional[str] = None) -> BacktestResult:
    """Wire-up used by the CLI module. Selects a strategy by name + runs."""
    from .strategies.momentum import MomentumStrategy
    from .strategies.meanrev import MeanReversionStrategy

    strategies = {
        "momentum": MomentumStrategy(fast=12, slow=48),
        "meanrev":  MeanReversionStrategy(window=60, z_entry=1.5),
    }
    if strategy_name.lower() not in strategies:
        raise ValueError(f"unknown strategy {strategy_name!r}; choices: {list(strategies)}")
    strat = strategies[strategy_name.lower()]

    result = run_backtest(
        strategy=strat,
        prices_csv=prices_csv,
        asset=asset,
        initial_equity=initial_equity,
    )
    return result


if __name__ == "__main__":
    from .strategies.momentum import MomentumStrategy

    result = run_backtest(
        strategy=MomentumStrategy(fast=12, slow=48),
        asset="BTC",
        initial_equity=10_000.0,
    )
    print(json.dumps(result.summary(), indent=2))
