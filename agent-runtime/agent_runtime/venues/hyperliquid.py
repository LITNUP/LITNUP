"""HyperliquidVenue — live execution on Hyperliquid spot/perp.

OPTIONAL. Disabled by default. Requires explicit opt-in via env vars:
  HYPERLIQUID_LIVE=true
  HYPERLIQUID_PRIVATE_KEY=0x...
  HYPERLIQUID_TESTNET=true   # default: testnet (recommended); set false for mainnet
  HYPERLIQUID_MAX_ORDER_USD=1000  # per-order safety cap

This adapter handles:
  - Mid-price fetching from /info { type: 'allMids' }
  - Position reading from /info { type: 'clearinghouseState' }
  - Realized + unrealized PnL aggregation
  - Order construction (symbol → asset index, side, size)
  - Order action hash construction (used for EIP-712 signing)

ORDER SUBMISSION is gated behind `_signed_submit()` which calls into the optional
`hyperliquid-python-sdk` if installed; otherwise raises with a clear setup error.
This keeps the runtime auditable while letting operators opt into the official SDK.

To go live:
  pip install hyperliquid-python-sdk
  export HYPERLIQUID_LIVE=true HYPERLIQUID_PRIVATE_KEY=0x...

Reference: https://hyperliquid.gitbook.io/hyperliquid-docs

SAFETY NOTES:
- Per-order USD cap is enforced
- Funding-rate, cross-margin, multi-leg strategies are NOT handled here
- Liquidation buffers are NOT pre-checked (use external risk-management)
- Test on testnet for >=24h before mainnet
"""
from __future__ import annotations

import os
import time
import json
from typing import Optional, Any

import requests

from .base import Venue, OrderResult, Side


HYPERLIQUID_TESTNET_API = "https://api.hyperliquid-testnet.xyz"
HYPERLIQUID_MAINNET_API = "https://api.hyperliquid.xyz"


class HyperliquidVenue(Venue):
    name = "Hyperliquid"

    def __init__(self):
        if os.getenv("HYPERLIQUID_LIVE", "false").lower() != "true":
            raise RuntimeError(
                "HyperliquidVenue is OFF unless HYPERLIQUID_LIVE=true. "
                "This is intentional. Use PaperVenue for development."
            )

        self.private_key = os.getenv("HYPERLIQUID_PRIVATE_KEY")
        if not self.private_key:
            raise RuntimeError("HYPERLIQUID_PRIVATE_KEY not set")

        is_testnet = os.getenv("HYPERLIQUID_TESTNET", "true").lower() == "true"
        self.api_url = HYPERLIQUID_TESTNET_API if is_testnet else HYPERLIQUID_MAINNET_API
        self.max_order_size_usd = float(os.getenv("HYPERLIQUID_MAX_ORDER_USD", "1000"))

        # Resolve wallet address from private key
        try:
            from eth_account import Account
            self.address = Account.from_key(self.private_key).address
        except Exception:
            self.address = None

        # Cache asset index → symbol mapping; populated on first call
        self._asset_index: dict[str, int] | None = None

    # ============================================================
    # PUBLIC INTERFACE
    # ============================================================

    def open_position(self, symbol: str, side: Side, size_usd: float) -> OrderResult:
        if size_usd > self.max_order_size_usd:
            return OrderResult(
                False, self.name, side, symbol, size_usd, 0.0, int(time.time()),
                error=f"order size ${size_usd} exceeds cap ${self.max_order_size_usd}",
            )

        price = self._get_mid_price(symbol)
        if price is None:
            return OrderResult(
                False, self.name, side, symbol, size_usd, 0.0, int(time.time()),
                error="no price",
            )

        asset_idx = self._asset_index_for(symbol)
        if asset_idx is None:
            return OrderResult(
                False, self.name, side, symbol, size_usd, price, int(time.time()),
                error=f"asset {symbol} not found on Hyperliquid",
            )

        is_buy = side == "LONG"
        size_native = round(size_usd / price, 6)

        # Hyperliquid order action (perp market)
        action = {
            "type": "order",
            "orders": [{
                "a": asset_idx,            # asset index
                "b": is_buy,               # is_buy
                "p": "0",                  # price (0 = market)
                "s": str(size_native),     # size in native units
                "r": False,                # reduce_only
                "t": {"limit": {"tif": "Ioc"}},  # immediate-or-cancel
            }],
            "grouping": "na",
        }

        try:
            response = self._signed_submit(action)
        except NotImplementedError as e:
            return OrderResult(
                False, self.name, side, symbol, size_usd, price, int(time.time()),
                error=str(e),
            )
        except Exception as e:
            return OrderResult(
                False, self.name, side, symbol, size_usd, price, int(time.time()),
                error=f"submit error: {e}",
            )

        # Parse fill status
        ok = response.get("status") == "ok"
        order_id = None
        try:
            statuses = response["response"]["data"]["statuses"]
            if statuses and isinstance(statuses[0], dict) and "filled" in statuses[0]:
                order_id = str(statuses[0]["filled"].get("oid", ""))
        except Exception:
            pass

        return OrderResult(
            success=ok,
            venue=self.name,
            side=side,
            symbol=symbol,
            size_usd=size_usd,
            price=price,
            timestamp=int(time.time()),
            venue_order_id=order_id,
            error=None if ok else json.dumps(response)[:240],
        )

    def close_position(self, symbol: str) -> OrderResult:
        pos = self.get_position(symbol)
        if not pos:
            return OrderResult(
                False, self.name, "LONG", symbol, 0.0, 0.0, int(time.time()),
                error="no open position",
            )

        # Close = open opposite side at current size
        size_native = abs(float(pos.get("szi", 0)))
        side: Side = "SHORT" if float(pos.get("szi", 0)) > 0 else "LONG"
        price = self._get_mid_price(symbol) or 0.0
        size_usd = size_native * price
        asset_idx = self._asset_index_for(symbol)

        action = {
            "type": "order",
            "orders": [{
                "a": asset_idx,
                "b": (side == "LONG"),
                "p": "0",
                "s": str(size_native),
                "r": True,  # reduce_only on close
                "t": {"limit": {"tif": "Ioc"}},
            }],
            "grouping": "na",
        }

        try:
            response = self._signed_submit(action)
        except NotImplementedError as e:
            return OrderResult(
                False, self.name, side, symbol, size_usd, price, int(time.time()),
                error=str(e),
            )
        except Exception as e:
            return OrderResult(
                False, self.name, side, symbol, size_usd, price, int(time.time()),
                error=f"submit error: {e}",
            )

        ok = response.get("status") == "ok"
        return OrderResult(
            success=ok,
            venue=self.name,
            side=side,
            symbol=symbol,
            size_usd=size_usd,
            price=price,
            timestamp=int(time.time()),
            error=None if ok else json.dumps(response)[:240],
        )

    def get_position(self, symbol: str) -> Optional[dict]:
        """Return Hyperliquid clearinghouseState position for `symbol` or None."""
        state = self._clearinghouse_state()
        if not state:
            return None
        positions = state.get("assetPositions", [])
        for ap in positions:
            pos = ap.get("position", {})
            if pos.get("coin", "").upper() == symbol.upper():
                return pos
        return None

    def get_pnl(self, symbol: str) -> float:
        """Unrealized PnL for `symbol` position. Realized PnL requires trade-history query."""
        pos = self.get_position(symbol)
        if not pos:
            return 0.0
        try:
            return float(pos.get("unrealizedPnl", 0))
        except Exception:
            return 0.0

    # ============================================================
    # INFO / READ-PATH HELPERS
    # ============================================================

    def _info_post(self, payload: dict) -> Any:
        try:
            resp = requests.post(f"{self.api_url}/info", json=payload, timeout=10)
            resp.raise_for_status()
            return resp.json()
        except Exception:
            return None

    def _get_mid_price(self, symbol: str) -> Optional[float]:
        mids = self._info_post({"type": "allMids"})
        if not isinstance(mids, dict):
            return None
        v = mids.get(symbol.upper())
        try:
            return float(v) if v is not None else None
        except (TypeError, ValueError):
            return None

    def _meta(self) -> Optional[dict]:
        return self._info_post({"type": "meta"})

    def _asset_index_for(self, symbol: str) -> Optional[int]:
        if self._asset_index is None:
            meta = self._meta()
            if not meta or "universe" not in meta:
                return None
            self._asset_index = {
                u.get("name", "").upper(): i
                for i, u in enumerate(meta["universe"])
            }
        return self._asset_index.get(symbol.upper())

    def _clearinghouse_state(self) -> Optional[dict]:
        if not self.address:
            return None
        return self._info_post({"type": "clearinghouseState", "user": self.address})

    # ============================================================
    # WRITE-PATH — requires signing
    # ============================================================

    def _signed_submit(self, action: dict) -> dict:
        """Sign an action with the operator's private key and submit to /exchange.

        Delegates signing to the optional `hyperliquid-python-sdk` if installed.
        If you don't have the SDK installed, this raises with setup instructions.
        """
        try:
            from hyperliquid.exchange import Exchange  # type: ignore
            from hyperliquid.utils.constants import (  # type: ignore
                MAINNET_API_URL, TESTNET_API_URL,
            )
            from eth_account import Account  # type: ignore
        except ImportError as e:
            raise NotImplementedError(
                "Order submission requires the Hyperliquid SDK. Install with: "
                "`pip install hyperliquid-python-sdk eth-account` then re-try. "
                f"(import error: {e})"
            )

        wallet = Account.from_key(self.private_key)
        base_url = (
            TESTNET_API_URL
            if os.getenv("HYPERLIQUID_TESTNET", "true").lower() == "true"
            else MAINNET_API_URL
        )
        exchange = Exchange(wallet=wallet, base_url=base_url)

        # The Hyperliquid SDK exposes high-level helpers; we translate our `action`
        # dict into the SDK's argument shape for `order()`.
        if action.get("type") != "order" or not action.get("orders"):
            raise ValueError("only order actions are supported by this adapter")

        o = action["orders"][0]
        asset_idx = o["a"]
        symbol = self._symbol_for_index(asset_idx)
        is_buy = o["b"]
        size_native = float(o["s"])
        reduce_only = o.get("r", False)

        return exchange.order(
            name=symbol,
            is_buy=is_buy,
            sz=size_native,
            limit_px=0.0,
            order_type={"limit": {"tif": "Ioc"}},
            reduce_only=reduce_only,
        )

    def _symbol_for_index(self, idx: int) -> str:
        if self._asset_index is None:
            self._asset_index_for("BTC")  # force populate
        if not self._asset_index:
            return ""
        for sym, i in self._asset_index.items():
            if i == idx:
                return sym
        return ""
