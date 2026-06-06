"""Price feeds for paper-trading agents.

Default: CoinGecko free tier — no API key required, 30 calls/min limit.
Production: Pyth Network on-chain feeds (manipulation-resistant).
"""
from __future__ import annotations

import os
import time
from dataclasses import dataclass
from typing import Optional

import requests


COINGECKO_BASE = "https://api.coingecko.com/api/v3"
SYMBOL_TO_CG_ID = {
    "BTC": "bitcoin",
    "ETH": "ethereum",
    "SOL": "solana",
    "ARB": "arbitrum",
    "OP":  "optimism",
}


@dataclass
class PriceTick:
    symbol: str
    price_usd: float
    timestamp: int  # unix seconds


class PriceFeed:
    """Simple polling price feed. Caches recent ticks to respect free-tier rate limits."""

    def __init__(self, api_key: Optional[str] = None, cache_seconds: int = 30):
        self.api_key = api_key or os.getenv("COINGECKO_API_KEY")
        self.cache_seconds = cache_seconds
        self._cache: dict[str, PriceTick] = {}

    def get_price(self, symbol: str) -> PriceTick:
        symbol = symbol.upper()
        cg_id = SYMBOL_TO_CG_ID.get(symbol)
        if not cg_id:
            raise ValueError(f"unknown symbol: {symbol}. Add it to SYMBOL_TO_CG_ID.")

        now = int(time.time())
        cached = self._cache.get(symbol)
        if cached and now - cached.timestamp < self.cache_seconds:
            return cached

        url = f"{COINGECKO_BASE}/simple/price"
        params = {"ids": cg_id, "vs_currencies": "usd"}
        headers = {}
        if self.api_key:
            headers["x-cg-pro-api-key"] = self.api_key

        try:
            resp = requests.get(url, params=params, headers=headers, timeout=10)
            resp.raise_for_status()
            data = resp.json()
            price = float(data[cg_id]["usd"])
        except Exception as e:
            # Fall back to last known price if available
            if cached:
                return cached
            raise RuntimeError(f"price feed failed for {symbol}: {e}") from e

        tick = PriceTick(symbol=symbol, price_usd=price, timestamp=now)
        self._cache[symbol] = tick
        return tick

    def get_history(self, symbol: str, days: int = 30) -> list[PriceTick]:
        """Pull historical daily prices for backtesting."""
        symbol = symbol.upper()
        cg_id = SYMBOL_TO_CG_ID.get(symbol)
        if not cg_id:
            raise ValueError(f"unknown symbol: {symbol}")

        url = f"{COINGECKO_BASE}/coins/{cg_id}/market_chart"
        params = {"vs_currency": "usd", "days": str(days), "interval": "daily"}
        headers = {}
        if self.api_key:
            headers["x-cg-pro-api-key"] = self.api_key

        resp = requests.get(url, params=params, headers=headers, timeout=15)
        resp.raise_for_status()
        prices = resp.json()["prices"]
        return [PriceTick(symbol=symbol, price_usd=float(p), timestamp=int(t / 1000)) for t, p in prices]
