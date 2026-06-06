"""Volatility carry strategy: harvest low-realized-vol regimes, exit when vol spikes.

Conceptually: short volatility when realized vol is low (paid for "stability").
We approximate this in long-only mode: long when realized vol is below a threshold,
flat when vol spikes (close + step aside until calm).

This pattern is profitable in calm markets; loses in vol expansions. Real strategies
hedge via VIX-like instruments. Use as a template.
"""
from __future__ import annotations

from statistics import stdev
from collections import deque

from .base import Strategy, Signal


class VolCarryStrategy(Strategy):
    name = "Vol-Carry"

    def __init__(self, window: int = 30, vol_threshold_bps: float = 200.0, vol_spike_bps: float = 500.0):
        super().__init__(lookback=window)
        self.window = window
        self.vol_threshold_bps = vol_threshold_bps
        self.vol_spike_bps = vol_spike_bps
        self._returns: deque[float] = deque(maxlen=window)
        self._last_price: float | None = None

    def _realized_vol_bps(self) -> float:
        if len(self._returns) < 3:
            return 0.0
        sd = stdev(self._returns)
        return sd * 10_000  # convert fractional return std to bps

    def step(self, price: float) -> Signal:
        if self._last_price is not None:
            r = (price - self._last_price) / self._last_price
            self._returns.append(r)
        self._last_price = price

        if not self.is_warm():
            return Signal("FLAT", 0.0, f"warming up ({len(self.prices)}/{self.lookback})")

        vol = self._realized_vol_bps()

        if vol >= self.vol_spike_bps:
            return Signal("FLAT", 1.0, f"vol spike {vol:.0f}bps ≥ {self.vol_spike_bps:.0f}bps — exit")

        if vol <= self.vol_threshold_bps:
            confidence = 1.0 - (vol / self.vol_threshold_bps)
            return Signal("LONG", confidence, f"calm regime; vol {vol:.0f}bps; carry on")

        return Signal("FLAT", 0.0, f"vol {vol:.0f}bps in transition zone")
