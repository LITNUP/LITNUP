"""Backtest + live performance metrics.

Standard suite: total return, annualized return, volatility, Sharpe, Sortino, Calmar,
max drawdown, drawdown duration, win rate, profit factor, expectancy, average trade,
turnover.

All inputs are equity curves (lists of floats) or trade lists. Math is plain Python +
the standard library; no numpy dep required for basic metrics, though numpy/pandas is
preferred for production backtests.
"""
from __future__ import annotations

import math
from dataclasses import dataclass


SECONDS_PER_YEAR = 365.25 * 24 * 60 * 60


@dataclass
class PerformanceReport:
    """All metrics derived from an equity curve."""
    initial_equity: float
    final_equity: float
    total_return_pct: float
    annualized_return_pct: float
    annualized_volatility_pct: float
    sharpe_ratio: float
    sortino_ratio: float
    calmar_ratio: float
    max_drawdown_pct: float
    max_drawdown_duration_seconds: int
    n_observations: int

    def __str__(self) -> str:
        return "\n".join([
            f"Initial equity:       ${self.initial_equity:,.2f}",
            f"Final equity:         ${self.final_equity:,.2f}",
            f"Total return:         {self.total_return_pct:+.2f}%",
            f"Annualized return:    {self.annualized_return_pct:+.2f}%",
            f"Annualized vol:       {self.annualized_volatility_pct:.2f}%",
            f"Sharpe ratio:         {self.sharpe_ratio:.2f}",
            f"Sortino ratio:        {self.sortino_ratio:.2f}",
            f"Calmar ratio:         {self.calmar_ratio:.2f}",
            f"Max drawdown:         {self.max_drawdown_pct:.2f}%",
            f"Max DD duration:      {self.max_drawdown_duration_seconds // 86400}d {self.max_drawdown_duration_seconds % 86400 // 3600}h",
            f"Observations:         {self.n_observations}",
        ])


def _returns_from_equity(equity: list[float]) -> list[float]:
    """Compute period-over-period simple returns."""
    if len(equity) < 2:
        return []
    out = []
    for i in range(1, len(equity)):
        prev = equity[i - 1]
        if prev <= 0:
            out.append(0.0)
        else:
            out.append((equity[i] - prev) / prev)
    return out


def _stdev(xs: list[float]) -> float:
    if len(xs) < 2:
        return 0.0
    mu = sum(xs) / len(xs)
    var = sum((x - mu) ** 2 for x in xs) / (len(xs) - 1)
    return math.sqrt(var)


def _downside_stdev(xs: list[float], target: float = 0.0) -> float:
    """Stdev of returns below `target`. Used for Sortino."""
    downside = [(x - target) ** 2 for x in xs if x < target]
    if not downside:
        return 0.0
    return math.sqrt(sum(downside) / len(xs))  # divides by n, not n_below — matches Sortino convention


def max_drawdown(equity: list[float]) -> tuple[float, int]:
    """Returns (max_drawdown_pct, peak_to_trough_index_distance).

    Drawdown is computed peak-to-trough from a running max.
    """
    if not equity:
        return 0.0, 0
    peak = equity[0]
    peak_idx = 0
    max_dd = 0.0
    max_dd_duration = 0
    for i, v in enumerate(equity):
        if v > peak:
            peak = v
            peak_idx = i
        dd = (peak - v) / peak if peak > 0 else 0.0
        if dd > max_dd:
            max_dd = dd
            max_dd_duration = i - peak_idx
    return max_dd, max_dd_duration


def performance_report(
    equity: list[float],
    interval_seconds: int = 86400,  # default daily; 60 for 1-minute, 14400 for 4-hour, etc.
    risk_free_rate: float = 0.0,
) -> PerformanceReport:
    """Compute the full suite of metrics from an equity curve.

    Args:
        equity: list of equity values, ordered chronologically
        interval_seconds: time between successive observations
        risk_free_rate: annualized RF rate (decimal, e.g. 0.04 for 4%)
    """
    if not equity:
        raise ValueError("equity curve is empty")

    n = len(equity)
    initial = equity[0]
    final = equity[-1]
    total_return = (final - initial) / initial if initial > 0 else 0.0

    returns = _returns_from_equity(equity)
    if not returns:
        return PerformanceReport(
            initial_equity=initial, final_equity=final,
            total_return_pct=total_return * 100,
            annualized_return_pct=0, annualized_volatility_pct=0,
            sharpe_ratio=0, sortino_ratio=0, calmar_ratio=0,
            max_drawdown_pct=0, max_drawdown_duration_seconds=0,
            n_observations=n,
        )

    periods_per_year = SECONDS_PER_YEAR / interval_seconds
    mean_r = sum(returns) / len(returns)
    sd_r = _stdev(returns)

    annualized_return = mean_r * periods_per_year
    annualized_vol = sd_r * math.sqrt(periods_per_year)

    excess_per_period = mean_r - (risk_free_rate / periods_per_year)
    sharpe = (excess_per_period / sd_r) * math.sqrt(periods_per_year) if sd_r > 0 else 0.0

    downside_sd = _downside_stdev(returns)
    sortino = (excess_per_period / downside_sd) * math.sqrt(periods_per_year) if downside_sd > 0 else 0.0

    max_dd, max_dd_steps = max_drawdown(equity)
    calmar = (annualized_return / max_dd) if max_dd > 0 else 0.0

    return PerformanceReport(
        initial_equity=initial,
        final_equity=final,
        total_return_pct=total_return * 100,
        annualized_return_pct=annualized_return * 100,
        annualized_volatility_pct=annualized_vol * 100,
        sharpe_ratio=sharpe,
        sortino_ratio=sortino,
        calmar_ratio=calmar,
        max_drawdown_pct=max_dd * 100,
        max_drawdown_duration_seconds=max_dd_steps * interval_seconds,
        n_observations=n,
    )


def trade_stats(trades: list[float]) -> dict:
    """Stats over a list of per-trade PnL values.

    trades: list of realized PnL per closed trade (positive = profit, negative = loss)
    """
    if not trades:
        return {"n_trades": 0}

    wins = [t for t in trades if t > 0]
    losses = [t for t in trades if t < 0]
    n = len(trades)
    win_rate = len(wins) / n if n > 0 else 0.0
    avg_win = sum(wins) / len(wins) if wins else 0.0
    avg_loss = sum(losses) / len(losses) if losses else 0.0
    gross_win = sum(wins)
    gross_loss = -sum(losses)  # positive number
    profit_factor = (gross_win / gross_loss) if gross_loss > 0 else float("inf") if gross_win > 0 else 0.0
    expectancy = sum(trades) / n

    return {
        "n_trades": n,
        "win_rate": round(win_rate, 4),
        "avg_win": round(avg_win, 2),
        "avg_loss": round(avg_loss, 2),
        "gross_win": round(gross_win, 2),
        "gross_loss": round(gross_loss, 2),
        "profit_factor": round(profit_factor, 2) if profit_factor != float("inf") else "inf",
        "expectancy": round(expectancy, 2),
        "best_trade": round(max(trades), 2),
        "worst_trade": round(min(trades), 2),
    }
