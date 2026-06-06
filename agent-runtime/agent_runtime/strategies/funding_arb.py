"""Funding rate arbitrage strategy.

Real implementation: pulls funding rates from a perp DEX (Hyperliquid, dYdX, Drift)
and goes long when funding is negative (longs paid by shorts) or short when positive.

Paper template: simulates funding via short-window momentum reversal proxy.
Replace _funding_rate() with a real venue API call before going live.
"""
from __future__ import annotations

from collections import deque

from .base import Strategy, Signal


class FundingArbStrategy(Strategy):
    name = "Funding-Arb"

    def __init__(self, window: int = 8, threshold_bps: float = 5.0):
        # 8-tick window approximates a perp's 8-hour funding cycle if 1 tick = 1 hour
        super().__init__(lookback=window)
        self.window = window
        self.threshold_bps = threshold_bps
        self._returns: deque[float] = deque(maxlen=window)
        self._last_price: float | None = None

    def _funding_rate_bps(self) -> float:
        """Stub: returns synthetic per-cycle funding rate.

        Real impl: GET /info { type: 'metaAndAssetCtxs' } from Hyperliquid;
        extract `funding` field from the asset context.

        Heuristic: funding rate ≈ k * (recent return). When prices rallied,
        perps trade above spot, longs pay funding to shorts.
        """
        if len(self._returns) < self.window:
            return 0.0
        recent_return = sum(self._returns)
        return recent_return * 1_000  # convert to ~bps

    def step(self, price: float) -> Signal:
        if self._last_price is not None:
            r = (price - self._last_price) / self._last_price
            self._returns.append(r)
        self._last_price = price

        if not self.is_warm():
            return Signal("FLAT", 0.0, f"warming up ({len(self.prices)}/{self.lookback})")

        funding_bps = self._funding_rate_bps()
        confidence = min(abs(funding_bps) / 50.0, 1.0)

        if funding_bps <= -self.threshold_bps:
            # Negative funding: longs receive payments → go long
            return Signal("LONG", confidence, f"funding {funding_bps:.1f}bps negative; long pays")
        elif funding_bps >= self.threshold_bps:
            # Positive funding: shorts receive payments → ideally short, but long-only mode → flat
            return Signal("FLAT", confidence, f"funding {funding_bps:.1f}bps positive; long-only mode → flat")
        else:
            return Signal("FLAT", 0.0, f"funding {funding_bps:.1f}bps within band")
