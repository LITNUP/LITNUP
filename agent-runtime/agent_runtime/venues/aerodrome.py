"""AerodromeVenue — DEX execution on Aerodrome (Base mainnet).

OPTIONAL. Disabled by default. Requires explicit opt-in:
  AERODROME_LIVE=true
  AERODROME_PRIVATE_KEY=0x...
  BASE_RPC_URL=https://...
  AERODROME_MAX_SWAP_USD=1000

Aerodrome is the dominant DEX on Base. This adapter handles:
  - Pool / route discovery via the Router contract
  - Quote queries (`getAmountsOut`)
  - Swap submission with deadline + slippage protection

This adapter does NOT handle:
  - Stable vs volatile pool selection (we default to volatile for non-USDC pairs)
  - Multi-hop routing optimization (single-hop or 2-hop only)
  - LP position management (we are a swapper, not an LP)
  - Concentrated-liquidity / Slipstream pools (those use a different router)

For full Aerodrome integration, use the Aerodrome SDK once it ships, or wrap
the contracts via viem directly. This module exists to give operators a
deterministic, auditable spot-execution path on Base.
"""
from __future__ import annotations

import os
import time
from typing import Optional

import requests

from .base import Venue, OrderResult, Side


# Canonical Aerodrome Router on Base mainnet
AERODROME_ROUTER = "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43"

# Common Base mainnet token addresses
TOKEN_REGISTRY = {
    "WETH": "0x4200000000000000000000000000000000000006",
    "USDC": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    "AERO": "0x940181a94A35A4569E4529A3CDfB74e38FD98631",
    "CBETH": "0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22",
    # $LITNUP will be added post-TGE
}

# Aerodrome Router minimal ABI subset
ROUTER_ABI_SUBSET = [
    {
        "type": "function",
        "name": "getAmountsOut",
        "stateMutability": "view",
        "inputs": [
            {"name": "amountIn", "type": "uint256"},
            {
                "name": "routes",
                "type": "tuple[]",
                "components": [
                    {"name": "from", "type": "address"},
                    {"name": "to", "type": "address"},
                    {"name": "stable", "type": "bool"},
                    {"name": "factory", "type": "address"},
                ],
            },
        ],
        "outputs": [{"name": "amounts", "type": "uint256[]"}],
    },
    {
        "type": "function",
        "name": "swapExactTokensForTokens",
        "stateMutability": "nonpayable",
        "inputs": [
            {"name": "amountIn", "type": "uint256"},
            {"name": "amountOutMin", "type": "uint256"},
            {
                "name": "routes",
                "type": "tuple[]",
                "components": [
                    {"name": "from", "type": "address"},
                    {"name": "to", "type": "address"},
                    {"name": "stable", "type": "bool"},
                    {"name": "factory", "type": "address"},
                ],
            },
            {"name": "to", "type": "address"},
            {"name": "deadline", "type": "uint256"},
        ],
        "outputs": [{"name": "amounts", "type": "uint256[]"}],
    },
]


class AerodromeVenue(Venue):
    name = "Aerodrome"

    def __init__(self):
        if os.getenv("AERODROME_LIVE", "false").lower() != "true":
            raise RuntimeError(
                "AerodromeVenue is OFF unless AERODROME_LIVE=true. "
                "This is intentional. Use PaperVenue for development."
            )

        self.private_key = os.getenv("AERODROME_PRIVATE_KEY")
        if not self.private_key:
            raise RuntimeError("AERODROME_PRIVATE_KEY not set")

        self.rpc_url = os.getenv("BASE_RPC_URL", "https://mainnet.base.org")
        self.max_swap_usd = float(os.getenv("AERODROME_MAX_SWAP_USD", "1000"))
        self.slippage_bps = int(os.getenv("AERODROME_MAX_SLIPPAGE_BPS", "50"))  # 0.5%

        # Lazy web3 init
        self._w3 = None
        self._router = None
        self._address = None

        # Track open "positions" — for a DEX, position == bag of base token currently held
        self._positions: dict[str, dict] = {}

    # ============================================================
    # WEB3 SETUP (lazy)
    # ============================================================

    def _web3(self):
        if self._w3 is None:
            try:
                from web3 import Web3  # type: ignore
                from eth_account import Account  # type: ignore
            except ImportError as e:
                raise NotImplementedError(
                    f"AerodromeVenue requires `web3` + `eth-account`. Install with: "
                    f"pip install web3 eth-account ({e})"
                )
            w3 = Web3(Web3.HTTPProvider(self.rpc_url))
            if not w3.is_connected():
                raise RuntimeError(f"cannot connect to {self.rpc_url}")
            self._w3 = w3
            self._router = w3.eth.contract(
                address=Web3.to_checksum_address(AERODROME_ROUTER),
                abi=ROUTER_ABI_SUBSET,
            )
            self._address = Account.from_key(self.private_key).address
        return self._w3

    # ============================================================
    # PUBLIC INTERFACE
    # ============================================================

    def open_position(self, symbol: str, side: Side, size_usd: float) -> OrderResult:
        """Aerodrome doesn't have LONG/SHORT — `side=LONG` means "swap USDC → symbol",
        `side=SHORT` means "swap symbol → USDC". We map directionality to swap direction.
        """
        if size_usd > self.max_swap_usd:
            return OrderResult(
                False, self.name, side, symbol, size_usd, 0.0, int(time.time()),
                error=f"swap size ${size_usd} exceeds cap ${self.max_swap_usd}",
            )

        target_token = TOKEN_REGISTRY.get(symbol.upper())
        if not target_token:
            return OrderResult(
                False, self.name, side, symbol, size_usd, 0.0, int(time.time()),
                error=f"unknown token {symbol}",
            )

        try:
            self._web3()
        except Exception as e:
            return OrderResult(
                False, self.name, side, symbol, size_usd, 0.0, int(time.time()),
                error=str(e),
            )

        if side == "LONG":
            from_token = TOKEN_REGISTRY["USDC"]
            to_token = target_token
        else:
            from_token = target_token
            to_token = TOKEN_REGISTRY["USDC"]

        # USDC has 6 decimals on Base
        amount_in = int(size_usd * 1e6) if from_token == TOKEN_REGISTRY["USDC"] else int(size_usd * 1e18)

        # Quote
        try:
            quote = self._quote_amounts_out(from_token, to_token, amount_in)
        except Exception as e:
            return OrderResult(
                False, self.name, side, symbol, size_usd, 0.0, int(time.time()),
                error=f"quote failed: {e}",
            )
        if not quote or quote == 0:
            return OrderResult(
                False, self.name, side, symbol, size_usd, 0.0, int(time.time()),
                error="no liquidity for route",
            )

        min_out = quote * (10_000 - self.slippage_bps) // 10_000
        deadline = int(time.time()) + 300  # 5 minute window
        price = quote / amount_in if amount_in else 0.0

        try:
            tx_hash = self._execute_swap(
                from_token, to_token, amount_in, min_out, deadline,
            )
        except NotImplementedError as e:
            return OrderResult(
                False, self.name, side, symbol, size_usd, price, int(time.time()),
                error=str(e),
            )
        except Exception as e:
            return OrderResult(
                False, self.name, side, symbol, size_usd, price, int(time.time()),
                error=f"swap failed: {e}",
            )

        self._positions[symbol.upper()] = {
            "symbol": symbol.upper(),
            "side": side,
            "size_usd": size_usd,
            "entry_price": price,
            "tx_hash": tx_hash,
            "opened_at": int(time.time()),
        }

        return OrderResult(
            success=True,
            venue=self.name,
            side=side,
            symbol=symbol,
            size_usd=size_usd,
            price=price,
            timestamp=int(time.time()),
            venue_order_id=tx_hash,
        )

    def close_position(self, symbol: str) -> OrderResult:
        pos = self._positions.get(symbol.upper())
        if not pos:
            return OrderResult(
                False, self.name, "LONG", symbol, 0.0, 0.0, int(time.time()),
                error="no open position",
            )
        # Reverse the original swap
        reverse_side: Side = "SHORT" if pos["side"] == "LONG" else "LONG"
        result = self.open_position(symbol, reverse_side, pos["size_usd"])
        if result.success:
            self._positions.pop(symbol.upper(), None)
        return result

    def get_position(self, symbol: str) -> Optional[dict]:
        return self._positions.get(symbol.upper())

    def get_pnl(self, symbol: str) -> float:
        pos = self._positions.get(symbol.upper())
        if not pos:
            return 0.0
        # Approximate: would need current price to compute precisely
        # Stub returns 0 until we re-quote at close-time
        return 0.0

    # ============================================================
    # ROUTER HELPERS
    # ============================================================

    def _quote_amounts_out(self, from_token: str, to_token: str, amount_in: int) -> int:
        # Aerodrome route is a tuple (from, to, stable, factory). For now we try
        # volatile (stable=False) and fall back to stable on no-liquidity.
        from web3 import Web3  # type: ignore
        factory = "0x420DD381b31aEf6683db6B902084cB0FFECe40Da"  # AerodromeFactory on Base
        routes = [(
            Web3.to_checksum_address(from_token),
            Web3.to_checksum_address(to_token),
            False,
            Web3.to_checksum_address(factory),
        )]
        try:
            amounts = self._router.functions.getAmountsOut(amount_in, routes).call()
            return amounts[-1] if amounts else 0
        except Exception:
            # Try stable pool
            routes = [(
                Web3.to_checksum_address(from_token),
                Web3.to_checksum_address(to_token),
                True,
                Web3.to_checksum_address(factory),
            )]
            amounts = self._router.functions.getAmountsOut(amount_in, routes).call()
            return amounts[-1] if amounts else 0

    def _execute_swap(
        self,
        from_token: str,
        to_token: str,
        amount_in: int,
        min_out: int,
        deadline: int,
    ) -> str:
        """Build, sign, and broadcast the swap. Returns tx hash."""
        from web3 import Web3  # type: ignore
        from eth_account import Account  # type: ignore

        w3 = self._web3()
        factory = "0x420DD381b31aEf6683db6B902084cB0FFECe40Da"
        routes = [(
            Web3.to_checksum_address(from_token),
            Web3.to_checksum_address(to_token),
            False,
            Web3.to_checksum_address(factory),
        )]

        # Note: this assumes the operator has already approved the Router to spend
        # `from_token`. We do NOT auto-approve here — that requires a separate
        # ERC-20 approve transaction and is the operator's responsibility.

        tx = self._router.functions.swapExactTokensForTokens(
            amount_in,
            min_out,
            routes,
            Web3.to_checksum_address(self._address),
            deadline,
        ).build_transaction({
            "from": Web3.to_checksum_address(self._address),
            "nonce": w3.eth.get_transaction_count(self._address),
            "gas": 400_000,
            "maxFeePerGas": w3.to_wei("0.1", "gwei"),
            "maxPriorityFeePerGas": w3.to_wei("0.01", "gwei"),
            "chainId": w3.eth.chain_id,
        })

        signed = Account.from_key(self.private_key).sign_transaction(tx)
        raw = getattr(signed, "rawTransaction", None) or getattr(signed, "raw_transaction", None)
        tx_hash = w3.eth.send_raw_transaction(raw)
        return tx_hash.hex()
