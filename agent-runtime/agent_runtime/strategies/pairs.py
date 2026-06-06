"""Pairs trade strategy — cointegration-style mean reversion.

Conceptually: long a synthetic spread when it's mean-reverting away from its long-run
relationship. For real cointegration, use Engle-Granger or Johansen tests; this template
uses a simpler rolling-OLS hedge ratio approximation.

Single-asset adapter: since the LITNUP runtime is single-asset by default, this
template trades the residual between a primary asset and a "reference" series passed
in at construction. In production, swap `_reference_price()` for a real second-asset feed.
"""
from __future__ import annotations

from collections import deque
from statistics import mean, stdev

from .base import Strategy, Signal


class PairsTradeStrategy(Strategy):
    name = "Pairs-Trade"

    def __init__(
        self,
        window: int = 60,
        z_entry: float = 2.0,
        z_exit: float = 0.5,
        ref_drift: float = 0.0001,
    ):
        super().__init__(lookback=window)
        self.window = window
        self.z_entry = z_entry
        self.z_exit = z_exit
        self.ref_drift = ref_drift

        # In production, replace this with a real second-asset price feed.
        # For paper-trading we synthesize a slowly drifting reference and compute
        # the residual asset_price - hedge_ratio * reference.
        self._refs: deque[float] = deque(maxlen=window)
        self._spreads: deque[float] = deque(maxlen=window)
        self._last_price: float | None = None
        self._reference: float = 0.0
        self._reference_seeded = False

    def _reference_price(self, asset_price: float) -> float:
        """Synthesize a reference price that has long-run cointegration with the asset.

        Real implementation: pull a second asset (e.g. ETH if asset is BTC) from a price feed.
        """
        if not self._reference_seeded:
            self._reference = asset_price
            self._reference_seeded = True
        # Drift the reference slowly toward the asset (simulating cointegration with noise)
        self._reference += (asset_price - self._reference) * self.ref_drift
        return self._reference

    def step(self, price: float) -> Signal:
        ref = self._reference_price(price)
        # Hedge ratio: rolling OLS slope is overkill here; assume 1:1 for the template
        spread = price - ref
        self._spreads.append(spread)

        if len(self._spreads) < self.window:
            return Signal("FLAT", 0.0, f"warming up ({len(self._spreads)}/{self.window})")

        mu = mean(self._spreads)
        sd = stdev(self._spreads)
        if sd == 0:
            return Signal("FLAT", 0.0, "no spread variance")

        z = (spread - mu) / sd
        confidence = min(abs(z) / 3.0, 1.0)

        if z <= -self.z_entry:
            return Signal("LONG", confidence, f"spread {z:+.2f}σ below mean; long-revert")
        elif abs(z) <= self.z_exit:
            return Signal("FLAT", 0.0, f"spread converged; z={z:+.2f}; exit")
        else:
            return Signal("FLAT", 0.0, f"spread z={z:+.2f} in dead zone")
