"""Position + PnL accounting for paper-trading agents.

Tracks: open positions, realized PnL, unrealized PnL, high-water mark, drawdown.
Designed to mirror what `PerformanceOracle` will attest on-chain.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Literal


@dataclass
class Position:
    side: Literal["LONG", "SHORT"]
    size_usd: float        # notional in USD
    entry_price: float
    opened_at: int         # unix seconds


@dataclass
class Trade:
    ts: int
    action: str            # "OPEN_LONG", "CLOSE_LONG", "OPEN_SHORT", "CLOSE_SHORT"
    price: float
    size_usd: float
    realized_pnl_usd: float


class PnLTracker:
    """Single-asset, single-position PnL tracker.

    Capital denominated in USD. Realized PnL accumulates on close. Mark-to-market on every tick.
    """

    def __init__(self, initial_capital_usd: float = 10_000.0):
        self.initial_capital = initial_capital_usd
        self.cash = initial_capital_usd
        self.position: Position | None = None
        self.realized_pnl = 0.0
        self.unrealized_pnl = 0.0
        self.high_water_mark = initial_capital_usd
        self.trades: list[Trade] = []

    @property
    def equity(self) -> float:
        """cash + unrealized PnL."""
        return self.cash + self.unrealized_pnl

    @property
    def total_pnl(self) -> float:
        return self.equity - self.initial_capital

    @property
    def drawdown(self) -> float:
        """Drawdown as a fraction of HWM (positive number, 0..1)."""
        if self.high_water_mark <= 0:
            return 0.0
        return max(0.0, (self.high_water_mark - self.equity) / self.high_water_mark)

    def mark_to_market(self, price: float) -> None:
        """Update unrealized PnL given current price."""
        if self.position is None:
            self.unrealized_pnl = 0.0
        else:
            qty = self.position.size_usd / self.position.entry_price
            if self.position.side == "LONG":
                self.unrealized_pnl = qty * (price - self.position.entry_price)
            else:  # SHORT
                self.unrealized_pnl = qty * (self.position.entry_price - price)
        # Update HWM
        if self.equity > self.high_water_mark:
            self.high_water_mark = self.equity

    def open_long(self, price: float, size_usd: float) -> None:
        if self.position is not None:
            raise RuntimeError("already in a position")
        if size_usd > self.cash:
            size_usd = self.cash * 0.99  # leave buffer
        self.position = Position("LONG", size_usd, price, int(time.time()))
        self.cash -= size_usd
        self.trades.append(Trade(int(time.time()), "OPEN_LONG", price, size_usd, 0.0))

    def open_short(self, price: float, size_usd: float) -> None:
        if self.position is not None:
            raise RuntimeError("already in a position")
        # Paper short: no margin model; treat symmetrically to long
        self.position = Position("SHORT", size_usd, price, int(time.time()))
        self.trades.append(Trade(int(time.time()), "OPEN_SHORT", price, size_usd, 0.0))

    def close(self, price: float) -> float:
        """Close current position at price. Returns realized PnL."""
        if self.position is None:
            return 0.0
        qty = self.position.size_usd / self.position.entry_price
        if self.position.side == "LONG":
            pnl = qty * (price - self.position.entry_price)
            self.cash += self.position.size_usd + pnl
        else:
            pnl = qty * (self.position.entry_price - price)
            self.cash += pnl  # paper short: pretend cash was always there
        self.realized_pnl += pnl
        action = "CLOSE_LONG" if self.position.side == "LONG" else "CLOSE_SHORT"
        self.trades.append(Trade(int(time.time()), action, price, self.position.size_usd, pnl))
        self.position = None
        self.unrealized_pnl = 0.0
        # Update HWM
        if self.equity > self.high_water_mark:
            self.high_water_mark = self.equity
        return pnl

    def summary(self) -> dict:
        return {
            "initial_capital": round(self.initial_capital, 2),
            "equity": round(self.equity, 2),
            "cash": round(self.cash, 2),
            "realized_pnl": round(self.realized_pnl, 2),
            "unrealized_pnl": round(self.unrealized_pnl, 2),
            "total_pnl": round(self.total_pnl, 2),
            "total_return_pct": round(self.total_pnl / self.initial_capital * 100, 2),
            "high_water_mark": round(self.high_water_mark, 2),
            "drawdown_pct": round(self.drawdown * 100, 2),
            "open_position": self.position.side if self.position else "FLAT",
            "trade_count": len(self.trades),
        }
