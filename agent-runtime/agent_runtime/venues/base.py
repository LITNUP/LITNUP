"""Venue abstract base — all execution venues conform to this interface."""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Literal


Side = Literal["LONG", "SHORT"]


@dataclass
class OrderResult:
    success: bool
    venue: str
    side: Side
    symbol: str
    size_usd: float
    price: float
    timestamp: int
    venue_order_id: str | None = None
    error: str | None = None


class Venue(ABC):
    """Abstract execution venue. Subclasses implement open/close for a specific exchange."""

    name: str = "Base"

    @abstractmethod
    def open_position(self, symbol: str, side: Side, size_usd: float) -> OrderResult:
        ...

    @abstractmethod
    def close_position(self, symbol: str) -> OrderResult:
        ...

    @abstractmethod
    def get_position(self, symbol: str) -> dict | None:
        """Return current position info or None if flat."""
        ...

    @abstractmethod
    def get_pnl(self, symbol: str) -> float:
        """Return realized + unrealized PnL in USD for the symbol's position."""
        ...
