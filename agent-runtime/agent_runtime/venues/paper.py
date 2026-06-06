"""PaperVenue — local paper-trading. No real orders. Used in dev + testnet."""
from __future__ import annotations

import time

from .base import Venue, OrderResult, Side
from ..pnl_tracker import PnLTracker


class PaperVenue(Venue):
    name = "Paper"

    def __init__(self, initial_capital_usd: float = 10_000.0):
        self.tracker = PnLTracker(initial_capital_usd)

    def open_position(self, symbol: str, side: Side, size_usd: float) -> OrderResult:
        # Caller passes current price via tracker.mark_to_market just before this in the agent loop.
        # Here we read the most recent position price as a proxy. For paper, we accept caller as truth.
        ts = int(time.time())
        if side == "LONG":
            self.tracker.open_long(price=self._last_price() or 0.0, size_usd=size_usd)
        else:
            self.tracker.open_short(price=self._last_price() or 0.0, size_usd=size_usd)
        return OrderResult(True, self.name, side, symbol, size_usd, self._last_price() or 0.0, ts, "paper-fill")

    def close_position(self, symbol: str) -> OrderResult:
        ts = int(time.time())
        if self.tracker.position is None:
            return OrderResult(False, self.name, "LONG", symbol, 0.0, 0.0, ts, error="no position")
        side = self.tracker.position.side
        size = self.tracker.position.size_usd
        pnl = self.tracker.close(self._last_price() or 0.0)
        return OrderResult(True, self.name, side, symbol, size, self._last_price() or 0.0, ts, f"paper-close-pnl={pnl:.2f}")

    def get_position(self, symbol: str) -> dict | None:
        if self.tracker.position is None:
            return None
        p = self.tracker.position
        return {"side": p.side, "size_usd": p.size_usd, "entry": p.entry_price, "opened_at": p.opened_at}

    def get_pnl(self, symbol: str) -> float:
        return self.tracker.realized_pnl + self.tracker.unrealized_pnl

    # Helper: paper venue uses last price set externally. In real deployment, this would
    # ping CoinGecko / Pyth. For the paper case we just track the last price the agent saw.
    _last_price_value: float | None = None

    def update_last_price(self, price: float) -> None:
        self._last_price_value = price
        self.tracker.mark_to_market(price)

    def _last_price(self) -> float | None:
        return self._last_price_value
