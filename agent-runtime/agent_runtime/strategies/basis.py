"""Basis trade strategy: long spot + short perp when funding is rich; flat otherwise.

For a paper-trading demo we approximate basis with a synthetic "funding rate proxy"
(in reality, you'd pull funding from Hyperliquid / Drift / Binance directly).

This strategy is deliberately simple. Real basis trades involve careful risk management,
funding-rate forecasting, and counterparty selection. Treat this as a TEMPLATE.
"""
from __future__ import annotations

from collections import deque

from .base import Strategy, Signal


class BasisTradeStrategy(Strategy):
    """Enters when synthetic basis exceeds threshold; exits when basis decays.

    This is conceptual: in production, replace _funding_proxy with a real funding-rate feed.
    """
    name = "Basis-Trade"

    def __init__(self, lookback: int = 30, basis_threshold_bps: float = 30.0):
        super().__init__(lookback=lookback)
        self.basis_threshold_bps = basis_threshold_bps
        self._returns: deque[float] = deque(maxlen=lookback)
        self._last_price: float | None = None

    def _funding_proxy(self) -> float:
        """Estimate funding rate from price-return autocorrelation as a proxy.

        Real basis uses the perp-spot funding payment (annualized 8h funding × 1095).
        Here we substitute a return-momentum proxy: when prices rally hard, perps
        often pay positive funding to longs, so basis is rich → carry the trade.
        """
        if len(self._returns) < 5:
            return 0.0
        recent = list(self._returns)[-5:]
        avg_return = sum(recent) / len(recent)
        # Convert per-tick return to bps annualized (very rough)
        return avg_return * 10_000

    def step(self, price: float) -> Signal:
        if self._last_price is not None:
            r = (price - self._last_price) / self._last_price
            self._returns.append(r)
        self._last_price = price

        if not self.is_warm():
            return Signal("FLAT", 0.0, f"warming up ({len(self.prices)}/{self.lookback})")

        basis = self._funding_proxy()
        confidence = min(abs(basis) / 100.0, 1.0)

        if basis >= self.basis_threshold_bps:
            return Signal(
                "LONG", confidence,
                f"synthetic basis {basis:.0f}bps ≥ threshold {self.basis_threshold_bps:.0f}bps; carry positive"
            )
        else:
            return Signal(
                "FLAT", 0.0,
                f"basis {basis:.0f}bps below threshold; no carry"
            )
