"""Strategy base class — all strategies inherit from this."""
from __future__ import annotations

from abc import ABC, abstractmethod
from collections import deque
from dataclasses import dataclass
from typing import Literal


SignalKind = Literal["LONG", "SHORT", "FLAT"]


@dataclass
class Signal:
    kind: SignalKind
    confidence: float  # 0..1
    reason: str        # human-readable explanation
    target_size: float = 1.0  # fraction of available capital, 0..1


class Strategy(ABC):
    """Abstract strategy. Implementations override `step(price)` to emit a Signal."""

    name: str = "Base"

    def __init__(self, lookback: int = 100):
        self.lookback = lookback
        self._prices: deque[float] = deque(maxlen=lookback)

    def feed(self, price: float) -> None:
        self._prices.append(price)

    def is_warm(self) -> bool:
        return len(self._prices) >= self.lookback

    @property
    def prices(self) -> list[float]:
        return list(self._prices)

    @abstractmethod
    def step(self, price: float) -> Signal:
        """Return a Signal given the current price (after `feed` already called)."""
        ...
