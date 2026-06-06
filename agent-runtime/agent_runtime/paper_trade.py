"""Paper-trading driver: runs an Agent for N minutes, prints a live table.

Usage:
  python -m agent_runtime.paper_trade --strategy momentum --asset BTC --duration 1h --interval 30s

After running, attestation logs are written to ./logs/.
"""
from __future__ import annotations

import argparse
import os
import re
import time
from dotenv import load_dotenv
from rich.console import Console
from rich.table import Table

from .agent import Agent, AgentConfig
from .strategies.momentum import MomentumStrategy
from .strategies.meanrev import MeanReversionStrategy


def parse_duration(s: str) -> int:
    """'1h' -> 3600, '30m' -> 1800, '90s' -> 90."""
    m = re.match(r"^(\d+)([smhd])$", s.strip().lower())
    if not m:
        raise ValueError(f"bad duration: {s!r}")
    n, unit = int(m.group(1)), m.group(2)
    return n * {"s": 1, "m": 60, "h": 3600, "d": 86400}[unit]


def build_strategy(name: str):
    name = name.lower()
    if name == "momentum":
        return MomentumStrategy(fast=12, slow=48)
    if name == "meanrev":
        return MeanReversionStrategy(window=60, z_entry=1.5)
    raise ValueError(f"unknown strategy: {name}")


def main():
    load_dotenv()

    p = argparse.ArgumentParser()
    p.add_argument("--strategy", choices=["momentum", "meanrev"], default="momentum")
    p.add_argument("--asset", default="BTC")
    p.add_argument("--duration", default="1h", help="e.g. 30m, 1h, 24h")
    p.add_argument("--interval", default="30s", help="time between ticks")
    p.add_argument("--capital", type=float, default=10_000.0)
    p.add_argument("--agent-id", type=int, default=1)
    args = p.parse_args()

    duration_s = parse_duration(args.duration)
    interval_s = parse_duration(args.interval)
    end_at = time.time() + duration_s

    cfg = AgentConfig(
        agent_id=args.agent_id,
        asset=args.asset,
        initial_capital_usd=args.capital,
        chain_id=int(os.getenv("CHAIN_ID", "84532")),
        oracle_address=os.getenv("PERFORMANCE_ORACLE_ADDRESS", "0x0000000000000000000000000000000000000000"),
    )
    signer_key = os.getenv("ORACLE_SIGNER_PRIVATE_KEY")
    agent = Agent(cfg=cfg, strategy=build_strategy(args.strategy), signer_private_key=signer_key)

    console = Console()
    console.print(f"[bold cyan]LITNUP[/] paper trader · agent {cfg.agent_id} · {cfg.asset} · {agent.strategy.name}")
    console.print(f"Capital ${cfg.initial_capital_usd:,.0f} · Duration {args.duration} · Interval {args.interval}")
    console.print(f"Signer: {'configured' if signer_key else '[red]NOT configured[/] (run scripts/gen_signer.py to enable attestations)'}")
    console.print()

    table = Table(show_header=True, header_style="bold magenta")
    for col in ["Time", "Price", "Signal", "Conf", "Action", "Equity", "PnL%", "DD%"]:
        table.add_column(col, justify="right" if col not in ("Time", "Signal", "Action") else "left")

    last_attest_at = time.time()
    attestation_interval = 60 * 60  # 1 hour for demo (4h in production)
    rows = []

    while time.time() < end_at:
        try:
            row = agent.tick()
        except Exception as e:
            console.print(f"[red]tick error:[/] {e}")
            time.sleep(interval_s)
            continue

        rows.append(row)
        # Render last 12 rows
        recent = rows[-12:]
        new_table = Table(show_header=True, header_style="bold magenta")
        for col in ["Time", "Price", "Signal", "Conf", "Action", "Equity", "PnL%", "DD%"]:
            new_table.add_column(col, justify="right" if col not in ("Time", "Signal", "Action") else "left")
        for r in recent:
            ts = time.strftime("%H:%M:%S", time.localtime(r["ts"]))
            pnl_pct = round(((r["equity"] - cfg.initial_capital_usd) / cfg.initial_capital_usd) * 100, 2)
            sig_color = {"LONG": "green", "SHORT": "red", "FLAT": "yellow"}.get(r["signal"], "white")
            new_table.add_row(
                ts, f"{r['price']:.2f}",
                f"[{sig_color}]{r['signal']}[/]",
                f"{r['confidence']:.2f}",
                r["action"],
                f"{r['equity']:,.2f}",
                f"{pnl_pct:+.2f}",
                f"{r['drawdown_pct']:.2f}",
            )

        console.clear()
        console.print(f"[bold cyan]LITNUP[/] · agent {cfg.agent_id} · {cfg.asset} · {agent.strategy.name}")
        console.print(new_table)
        console.print()
        console.print(f"[dim]Attestations:[/] {agent.epoch} signed | next in {int(attestation_interval - (time.time() - last_attest_at))}s")

        # Periodic attestation
        if time.time() - last_attest_at >= attestation_interval and signer_key:
            signed = agent.attest()
            if signed:
                console.print(f"[bold green]✓ Attestation #{agent.epoch} signed[/] by {signed['signer']}")
                console.print(f"  PnL delta: {int(signed['attestation']['pnlDelta']) / 1e18:+.2f} | Fee: {int(signed['attestation']['feeOnGross']) / 1e18:.2f}")
            last_attest_at = time.time()

        time.sleep(interval_s)

    # Final
    console.print()
    console.print("[bold]Final summary:[/]")
    summary = agent.pnl.summary()
    for k, v in summary.items():
        console.print(f"  {k}: {v}")


def run_paper_trade(strategy: str, asset: str, duration: str, interval: str,
                    initial_equity: float = 10_000.0, agent_id: int = 1):
    """Programmatic entrypoint mirroring main() — used by the CLI module."""
    import sys as _sys
    _sys.argv = [
        "paper_trade",
        "--strategy", strategy,
        "--asset", asset,
        "--duration", duration,
        "--interval", interval,
        "--capital", str(initial_equity),
        "--agent-id", str(agent_id),
    ]
    main()


if __name__ == "__main__":
    main()
