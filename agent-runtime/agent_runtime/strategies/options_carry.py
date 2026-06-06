"""Options carry strategy — implied vs realized vol premium harvest.

Concept: when the implied volatility priced into options exceeds expected realized
volatility, short vol (sell options) for premium. When the spread reverses, exit.

Real implementation requires:
  - An options pricing data feed (Deribit, Lyra, Premia, etc.)
  - A volatility forecasting model (GARCH, HAR-RV, etc.)
  - A risk model for tail-of-distribution events

This template uses a simpler proxy: realized vol vs a synthetic "implied" derived
from a longer-window vol estimate. Long-only mode: enters when current vol is
materially below the long-run vol band (i.e. variance risk premium environment).

Use as a starting structure. Replace `_implied_vol_proxy` with a real data feed.
"""
from __future__ import annotations

from collections import deque
from statistics import stdev

from .base import Strategy, Signal


class OptionsCarryStrategy(Strategy):
    name = "Options-Carry"

    def __init__(
        self,
        short_window: int = 20,
        long_window: int = 90,
        min_spread_vol_pts: float = 1.5,
    ):
        super().__init__(lookback=long_window)
        self.short_window = short_window
        self.long_window = long_window
        self.min_spread_vol_pts = min_spread_vol_pts
        self._returns: deque[float] = deque(maxlen=long_window)
        self._last_price: float | None = None

    def _vol(self, n: int) -> float:
        if len(self._returns) < n + 1:
            return 0.0
        recent = list(self._returns)[-n:]
        if len(recent) < 2:
            return 0.0
        # Annualized vol in % points (assuming each return is a tick of equal duration)
        sd = stdev(recent)
        return sd * 100  # in vol-points (rough scaling)

    def _implied_vol_proxy(self) -> float:
        """Stub: returns a synthetic 'implied' vol.

        Real implementation: pull from Deribit or Lyra options chain (ATM 30-day IV).
        Stub: blend short + long realized with bias toward long-run mean (acts like
        sticky implied vol).
        """
        rv_short = self._vol(self.short_window)
        rv_long = self._vol(self.long_window)
        # Sticky bias: implied vol tends to over-estimate during calm periods
        # so add a small carry premium to the long-run estimate
        return rv_long + 1.0  # +1 vol-point premium baseline

    def step(self, price: float) -> Signal:
        if self._last_price is not None:
            r = (price - self._last_price) / self._last_price
            self._returns.append(r)
        self._last_price = price

        if len(self._returns) < self.long_window:
            return Signal("FLAT", 0.0, f"warming up ({len(self._returns)}/{self.long_window})")

        rv = self._vol(self.short_window)
        iv = self._implied_vol_proxy()
        spread = iv - rv

        if spread <= self.min_spread_vol_pts:
            return Signal("FLAT", 0.0, f"spread {spread:.1f}pts below threshold; no premium")

        confidence = min(spread / 5.0, 1.0)
        return Signal(
            "LONG", confidence,
            f"IV {iv:.1f} > RV {rv:.1f}; harvest {spread:.1f}pt premium"
        )
