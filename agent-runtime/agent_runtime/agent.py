"""Agent — orchestrator that wires together strategy, price feed, PnL, and oracle signer."""
from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from .pnl_tracker import PnLTracker
from .price_feed import PriceFeed
from .strategies.base import Strategy
from .oracle_signer import Attestation, sign_attestation


@dataclass
class AgentConfig:
    agent_id: int
    asset: str = "BTC"
    initial_capital_usd: float = 10_000.0
    fee_bps_on_profit: int = 1000  # 10%
    attestation_interval_seconds: int = 14_400  # 4 hours (matches on-chain spec)
    chain_id: int = 84532  # Base Sepolia
    oracle_address: str = "0x0000000000000000000000000000000000000000"
    log_dir: str = "./logs"


class Agent:
    """Stateful agent. Calls `tick()` on a schedule; `attest()` to produce a signed attestation."""

    def __init__(
        self,
        cfg: AgentConfig,
        strategy: Strategy,
        signer_private_key: Optional[str] = None,
    ):
        self.cfg = cfg
        self.strategy = strategy
        self.signer_private_key = signer_private_key
        self.feed = PriceFeed()
        self.pnl = PnLTracker(initial_capital_usd=cfg.initial_capital_usd)
        self.epoch = 0
        self._last_attest_pnl_usd = 0.0
        self._last_attest_at = int(time.time())
        Path(cfg.log_dir).mkdir(parents=True, exist_ok=True)

    def tick(self) -> dict:
        """One step: pull price, feed strategy, act on signal, mark to market."""
        tick = self.feed.get_price(self.cfg.asset)
        self.strategy.feed(tick.price_usd)
        signal = self.strategy.step(tick.price_usd)
        self.pnl.mark_to_market(tick.price_usd)

        # Trade decisions
        action = "HOLD"
        position = self.pnl.position
        if signal.kind == "LONG" and position is None:
            size = self.cfg.initial_capital_usd * signal.target_size
            self.pnl.open_long(tick.price_usd, size)
            action = "OPEN_LONG"
        elif signal.kind == "SHORT" and position is None:
            size = self.cfg.initial_capital_usd * signal.target_size
            self.pnl.open_short(tick.price_usd, size)
            action = "OPEN_SHORT"
        elif signal.kind == "FLAT" and position is not None:
            pnl_realized = self.pnl.close(tick.price_usd)
            action = f"CLOSE ({pnl_realized:+.2f})"
        elif signal.kind != "FLAT" and position is not None and position.side != signal.kind:
            # Reverse
            self.pnl.close(tick.price_usd)
            size = self.cfg.initial_capital_usd * signal.target_size
            if signal.kind == "LONG":
                self.pnl.open_long(tick.price_usd, size)
                action = "REVERSE_TO_LONG"
            else:
                self.pnl.open_short(tick.price_usd, size)
                action = "REVERSE_TO_SHORT"

        return {
            "ts": tick.timestamp,
            "asset": self.cfg.asset,
            "price": tick.price_usd,
            "signal": signal.kind,
            "confidence": round(signal.confidence, 3),
            "action": action,
            "equity": round(self.pnl.equity, 2),
            "drawdown_pct": round(self.pnl.drawdown * 100, 2),
        }

    def attest(self) -> Optional[dict]:
        """Produce a signed attestation reflecting PnL since the last attestation.

        Note: scales USD-PnL into protocol-token-units 1:1 for paper-trading purposes.
        Real protocol integration uses a price oracle to convert USD-denominated PnL into $LITNUP.
        """
        if not self.signer_private_key:
            return None

        now = int(time.time())
        # PnL delta since last attestation (USD; scaled to 1e18 token units)
        equity_now = self.pnl.equity
        equity_prev = self.cfg.initial_capital_usd + self._last_attest_pnl_usd
        delta_usd = equity_now - equity_prev

        # Fee only on positive PnL
        fee_usd = max(0.0, delta_usd) * (self.cfg.fee_bps_on_profit / 10_000.0)

        att = Attestation(
            agent_id=self.cfg.agent_id,
            pnl_delta_wei=int(delta_usd * 1e18),
            fee_on_gross_wei=int(fee_usd * 1e18),
            epoch=self.epoch + 1,
            deadline=now + 3600,
        )
        signed = sign_attestation(att, self.signer_private_key, self.cfg.chain_id, self.cfg.oracle_address)

        # Persist
        self.epoch += 1
        self._last_attest_pnl_usd = self.pnl.total_pnl
        self._last_attest_at = now

        out_path = Path(self.cfg.log_dir) / f"attestation-agent{self.cfg.agent_id}-epoch{self.epoch}.json"
        out_path.write_text(json.dumps(signed, indent=2))

        return signed
