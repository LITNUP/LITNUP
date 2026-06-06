"""Simple SMA crossover momentum strategy.

LONG when fast SMA crosses above slow SMA.
FLAT (close) when fast SMA crosses below slow SMA.
SHORT optional (disabled by default for simplicity / regulatory hygiene on longs-only).
"""
from __future__ import annotations

from .base import Strategy, Signal


class MomentumStrategy(Strategy):
    name = "Momentum-SMA"

    def __init__(self, fast: int = 12, slow: int = 48, allow_short: bool = False):
        if fast >= slow:
            raise ValueError("fast must be < slow")
        super().__init__(lookback=slow)
        self.fast = fast
        self.slow = slow
        self.allow_short = allow_short
        self._last_kind: str = "FLAT"

    def _sma(self, n: int) -> float:
        ps = self.prices[-n:]
        return sum(ps) / len(ps)

    def step(self, price: float) -> Signal:
        if not self.is_warm():
            return Signal("FLAT", 0.0, f"warming up ({len(self.prices)}/{self.slow})")

        fast_sma = self._sma(self.fast)
        slow_sma = self._sma(self.slow)
        spread_bps = (fast_sma - slow_sma) / slow_sma * 10_000

        # Confidence rises with the magnitude of the spread (capped)
        confidence = min(abs(spread_bps) / 100.0, 1.0)

        if fast_sma > slow_sma:
            kind = "LONG"
            reason = f"fast SMA ({fast_sma:.2f}) > slow SMA ({slow_sma:.2f}); spread {spread_bps:+.0f} bps"
        elif self.allow_short:
            kind = "SHORT"
            reason = f"fast SMA ({fast_sma:.2f}) < slow SMA ({slow_sma:.2f}); spread {spread_bps:+.0f} bps"
        else:
            kind = "FLAT"
            reason = f"fast SMA below slow SMA; long-only mode → FLAT"

        return Signal(kind, confidence, reason)
