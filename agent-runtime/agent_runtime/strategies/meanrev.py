"""Mean reversion strategy using rolling z-score.

LONG when price is z standard deviations BELOW the rolling mean.
FLAT when within band.
SHORT (optional) when price is z standard deviations ABOVE.
"""
from __future__ import annotations

from statistics import mean, stdev

from .base import Strategy, Signal


class MeanReversionStrategy(Strategy):
    name = "MeanReversion-Zscore"

    def __init__(self, window: int = 60, z_entry: float = 1.5, allow_short: bool = False):
        super().__init__(lookback=window)
        self.window = window
        self.z_entry = z_entry
        self.allow_short = allow_short

    def step(self, price: float) -> Signal:
        if not self.is_warm():
            return Signal("FLAT", 0.0, f"warming up ({len(self.prices)}/{self.window})")

        ps = self.prices
        mu = mean(ps)
        sd = stdev(ps) if len(ps) > 1 else 0.0
        if sd == 0:
            return Signal("FLAT", 0.0, "no variance in window")

        z = (price - mu) / sd
        confidence = min(abs(z) / 3.0, 1.0)

        if z <= -self.z_entry:
            return Signal("LONG", confidence, f"price {z:+.2f}σ below mean (mu={mu:.2f}, sd={sd:.2f})")
        elif z >= self.z_entry and self.allow_short:
            return Signal("SHORT", confidence, f"price {z:+.2f}σ above mean")
        else:
            return Signal("FLAT", 0.0, f"z={z:+.2f} within band ±{self.z_entry}")
