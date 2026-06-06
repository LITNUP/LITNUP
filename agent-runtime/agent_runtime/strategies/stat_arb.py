"""Statistical arbitrage: pairs-trade-style mean reversion against a synthetic benchmark.

For single-asset use, we pair the asset against its own EMA-decayed level and trade
the residual back to the level. In production, this would be a true pairs trade
(e.g. ETH vs BTC × beta) using cointegration.

This strategy is more sensitive than naive mean-reversion: it uses a half-life-aware
EMA rather than equal-weighted SMA, which reduces lag at the cost of more responsive
(noisier) signals.
"""
from __future__ import annotations

from collections import deque

from .base import Strategy, Signal


class StatArbStrategy(Strategy):
    name = "StatArb-EMA"

    def __init__(self, half_life: int = 24, z_entry: float = 1.5, z_exit: float = 0.5):
        # We don't strictly need a deque since EMA is recursive, but keep parent semantics
        super().__init__(lookback=max(half_life * 4, 50))
        self.half_life = half_life
        self.z_entry = z_entry
        self.z_exit = z_exit
        # EMA decay factor: alpha so that half-decay is at `half_life` steps
        self.alpha = 1 - 0.5 ** (1.0 / half_life)
        self.ema: float | None = None
        self.ema_var: float | None = None  # exponentially-weighted variance

    def step(self, price: float) -> Signal:
        if self.ema is None:
            self.ema = price
            self.ema_var = 0.0
            return Signal("FLAT", 0.0, "EMA bootstrap")

        # Update EMA + EMA-variance
        prev_ema = self.ema
        self.ema = self.alpha * price + (1 - self.alpha) * self.ema
        delta = price - prev_ema
        self.ema_var = (1 - self.alpha) * (self.ema_var + self.alpha * delta * delta)

        if self.ema_var <= 0 or not self.is_warm():
            return Signal("FLAT", 0.0, f"warming up ({len(self.prices)}/{self.lookback})")

        sigma = self.ema_var ** 0.5
        z = (price - self.ema) / sigma
        confidence = min(abs(z) / 3.0, 1.0)

        if z <= -self.z_entry:
            return Signal("LONG", confidence, f"residual z={z:+.2f} below entry; long mean-reversion")
        elif abs(z) <= self.z_exit:
            return Signal("FLAT", 0.0, f"residual converged; z={z:+.2f}; exit")
        elif z >= self.z_entry:
            return Signal("FLAT", confidence, f"residual {z:+.2f}σ above mean; long-only mode → flat")
        else:
            return Signal("FLAT", 0.0, f"residual z={z:+.2f} in dead zone")
