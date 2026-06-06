"""Tests for the metrics module."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from agent_runtime.metrics import (
    performance_report,
    max_drawdown,
    trade_stats,
)


def test_max_drawdown_simple():
    eq = [100, 110, 105, 95, 100, 90, 95]
    dd, dur = max_drawdown(eq)
    # Peak at idx 1 (110); trough at idx 5 (90). DD = (110-90)/110 ≈ 0.1818
    assert abs(dd - 20 / 110) < 1e-6
    assert dur == 4  # idx 5 - idx 1


def test_no_drawdown():
    eq = [100, 110, 120, 130]
    dd, _ = max_drawdown(eq)
    assert dd == 0


def test_performance_report_flat():
    eq = [100, 100, 100, 100]
    r = performance_report(eq, interval_seconds=86400)
    assert r.total_return_pct == 0
    assert r.sharpe_ratio == 0
    assert r.max_drawdown_pct == 0


def test_performance_report_growth():
    # 1% per day for 100 days
    eq = [100 * (1.01 ** i) for i in range(101)]
    r = performance_report(eq, interval_seconds=86400)
    assert r.total_return_pct > 100  # at least 100% over 100 days at 1%/day
    assert r.sharpe_ratio > 5  # very high since vol is 0


def test_trade_stats_basic():
    trades = [100, -50, 200, -30, 150, -80]
    s = trade_stats(trades)
    assert s["n_trades"] == 6
    assert s["win_rate"] == 0.5
    assert s["best_trade"] == 200
    assert s["worst_trade"] == -80
    assert s["expectancy"] > 0


def test_empty_trades():
    s = trade_stats([])
    assert s == {"n_trades": 0}


if __name__ == "__main__":
    test_max_drawdown_simple()
    test_no_drawdown()
    test_performance_report_flat()
    test_performance_report_growth()
    test_trade_stats_basic()
    test_empty_trades()
    print("All metrics tests passed ✓")
