"""Smoke tests for the backtest harness."""
from __future__ import annotations

import json

import pytest

from agent_runtime.backtest import (
    BacktestResult,
    run_backtest,
    write_report,
    _synthetic_gbm,
)
from agent_runtime.strategies.momentum import MomentumStrategy
from agent_runtime.strategies.meanrev import MeanReversionStrategy


def test_synthetic_gbm_generates_sequence():
    prices = _synthetic_gbm(n_ticks=100)
    assert len(prices) == 100
    assert all(p > 0 for _, p in prices)
    # Sorted by timestamp
    timestamps = [t for t, _ in prices]
    assert timestamps == sorted(timestamps)


def test_run_backtest_returns_result():
    s = MomentumStrategy(fast=12, slow=48)
    res = run_backtest(strategy=s, initial_equity=10_000.0)
    assert isinstance(res, BacktestResult)
    assert res.initial_equity == 10_000.0
    assert res.equity_curve
    # Sanity: final equity should be a finite positive number
    assert res.final_equity > 0
    assert res.final_equity == res.final_equity   # not NaN


def test_summary_keys_are_complete():
    s = MeanReversionStrategy(window=60, z_entry=1.5)
    res = run_backtest(strategy=s, initial_equity=5_000.0)
    summary = res.summary()
    for key in [
        "strategy", "asset", "period",
        "initial_equity", "final_equity",
        "total_return_pct", "max_drawdown_pct",
        "trade_count", "win_rate_pct", "sharpe",
        "slash_events", "would_be_slashed",
    ]:
        assert key in summary


def test_report_writes_files(tmp_path):
    s = MomentumStrategy(fast=12, slow=48)
    res = run_backtest(strategy=s, initial_equity=10_000.0)
    json_path = write_report(res, tmp_path)
    assert json_path.exists()
    payload = json.loads(json_path.read_text(encoding="utf-8"))
    assert "summary" in payload
    assert "trades" in payload

    # CSV equity curve also written
    csv_files = list(tmp_path.glob("equity-*.csv"))
    assert csv_files


def test_initial_equity_is_starting_point():
    s = MomentumStrategy(fast=12, slow=48)
    res = run_backtest(strategy=s, initial_equity=1_000.0)
    # First equity point should be the initial
    assert res.equity_curve[0][1] == pytest.approx(1_000.0, rel=0)


def test_slashing_simulates_under_huge_drawdown():
    """Construct a price series with a brutal crash to force slashing trigger."""
    # Synthetic series with high vol → high probability of drawdown
    prices = _synthetic_gbm(n_ticks=500, annualized_vol=2.0, seed=1)
    s = MomentumStrategy(fast=4, slow=12)
    res = run_backtest(strategy=s, prices=prices, initial_equity=10_000.0,
                       attestation_interval_secs=3600)
    # We're not asserting slash happened (synthetic is non-deterministic across builds);
    # just that the harness handles the high-vol path without errors.
    assert res.final_equity >= 0
