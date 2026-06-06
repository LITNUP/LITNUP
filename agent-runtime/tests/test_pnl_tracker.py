"""Tests for PnLTracker."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from agent_runtime.pnl_tracker import PnLTracker


def test_initial_state():
    p = PnLTracker(initial_capital_usd=10_000)
    assert p.cash == 10_000
    assert p.position is None
    assert p.equity == 10_000
    assert p.drawdown == 0


def test_long_profit():
    p = PnLTracker(10_000)
    p.open_long(100.0, 1_000)  # 10 units
    assert p.position is not None
    p.mark_to_market(110.0)
    assert abs(p.unrealized_pnl - 100.0) < 1e-6  # 10 units * $10 gain
    pnl = p.close(110.0)
    assert abs(pnl - 100.0) < 1e-6
    assert p.position is None
    assert abs(p.realized_pnl - 100.0) < 1e-6
    # Cash returns: original investment + profit
    assert abs(p.cash - 10_100.0) < 1e-6


def test_long_loss():
    p = PnLTracker(10_000)
    p.open_long(100.0, 1_000)
    p.mark_to_market(90.0)
    pnl = p.close(90.0)
    assert pnl < 0
    assert abs(pnl + 100.0) < 1e-6


def test_drawdown_tracking():
    p = PnLTracker(10_000)
    p.open_long(100.0, 1_000)
    p.mark_to_market(110.0)
    assert p.high_water_mark == p.equity == 10_100
    p.mark_to_market(95.0)
    assert p.drawdown > 0
    # Drawdown is 50/10100 ≈ 0.495%
    assert abs(p.drawdown - 50 / 10_100) < 1e-6


def test_cannot_open_two_positions():
    p = PnLTracker(10_000)
    p.open_long(100.0, 1_000)
    try:
        p.open_long(100.0, 1_000)
        assert False, "should have raised"
    except RuntimeError:
        pass


if __name__ == "__main__":
    test_initial_state()
    test_long_profit()
    test_long_loss()
    test_drawdown_tracking()
    test_cannot_open_two_positions()
    print("All PnLTracker tests passed ✓")
