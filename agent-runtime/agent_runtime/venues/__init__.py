"""Execution venues for LITNUP agents.

Each venue is an adapter that translates protocol-level decisions
(open/close long, open/close short) into venue-specific operations.

Default: paper-trading only (no real funds).
Optional live venues require explicit env-var opt-in.

Available venues:
  - PaperVenue       : in-memory simulation (always safe)
  - HyperliquidVenue : Hyperliquid perp/spot (HYPERLIQUID_LIVE=true)
  - AerodromeVenue   : Aerodrome DEX on Base (AERODROME_LIVE=true)
"""
from .base import Venue, OrderResult
from .paper import PaperVenue
from .hyperliquid import HyperliquidVenue
from .aerodrome import AerodromeVenue

__all__ = ["Venue", "OrderResult", "PaperVenue", "HyperliquidVenue", "AerodromeVenue"]
