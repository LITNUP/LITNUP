"""Backtest a strategy on historical CoinGecko data.

Usage:
  python scripts/backtest.py --strategy momentum --asset BTC --days 90
"""
from __future__ import annotations

import argparse
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from agent_runtime.price_feed import PriceFeed
from agent_runtime.pnl_tracker import PnLTracker
from agent_runtime.strategies.momentum import MomentumStrategy
from agent_runtime.strategies.meanrev import MeanReversionStrategy


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--strategy", choices=["momentum", "meanrev"], default="momentum")
    p.add_argument("--asset", default="BTC")
    p.add_argument("--days", type=int, default=90)
    p.add_argument("--capital", type=float, default=10_000.0)
    args = p.parse_args()

    feed = PriceFeed()
    history = feed.get_history(args.asset, days=args.days)
    print(f"Loaded {len(history)} daily bars for {args.asset} over {args.days} days.")

    if args.strategy == "momentum":
        strat = MomentumStrategy(fast=5, slow=20)  # daily timeframe — shorter windows
    else:
        strat = MeanReversionStrategy(window=20, z_entry=1.5)

    pnl = PnLTracker(initial_capital_usd=args.capital)

    last_price = None
    n_open = 0
    n_close = 0
    for tick in history:
        strat.feed(tick.price_usd)
        sig = strat.step(tick.price_usd)
        pnl.mark_to_market(tick.price_usd)

        pos = pnl.position
        if sig.kind == "LONG" and pos is None:
            pnl.open_long(tick.price_usd, args.capital)
            n_open += 1
        elif sig.kind == "FLAT" and pos is not None:
            pnl.close(tick.price_usd)
            n_close += 1
        last_price = tick.price_usd

    if pnl.position is not None and last_price is not None:
        pnl.close(last_price)

    print()
    print("=" * 60)
    print(f"Strategy: {strat.name}")
    print(f"Asset:    {args.asset}")
    print(f"Days:     {args.days}")
    print(f"Trades:   {n_open} opens / {n_close} closes")
    print("=" * 60)
    for k, v in pnl.summary().items():
        print(f"  {k:25} {v}")


if __name__ == "__main__":
    main()
