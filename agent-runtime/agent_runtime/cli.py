"""litnup-cli — operator-facing command-line tool for LITNUP.

Designed for operators running their own agents. Wraps the most-common workflows
into typed subcommands. Uses Click for argument parsing + Rich for output.

Usage examples:
    litnup-cli init                        # Scaffold a new operator repo
    litnup-cli config show
    litnup-cli paper-trade --strategy momentum --asset BTC --duration 1h
    litnup-cli backtest --strategy momentum --asset BTC --start 2025-01-01
    litnup-cli enroll --bond 50000 --metadata-uri ipfs://... --network base-sepolia
    litnup-cli oracle-sign --epoch 12 --pnl-delta 1234
    litnup-cli vault status --agent-id 7
    litnup-cli operator stats
    litnup-cli monitor --agent-id 7

Configuration is loaded from `.env` in the working directory + optional
`litnup.toml`. Network defaults to `base-sepolia`.
"""
from __future__ import annotations

import json
import os
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

try:
    import click
    from rich.console import Console
    from rich.table import Table
    from rich.panel import Panel
    from rich import box
except ImportError:
    print("Missing dependencies. Run: pip install click rich python-dotenv web3 eth-account")
    sys.exit(1)

from dotenv import load_dotenv


CONSOLE = Console()


# ===========================================================================
# Helpers
# ===========================================================================

def _load_env(env_path: Optional[str] = None):
    """Load .env from cwd or specified path."""
    if env_path:
        load_dotenv(env_path)
    else:
        load_dotenv()


def _require_env(key: str) -> str:
    v = os.getenv(key)
    if not v:
        CONSOLE.print(f"[red]error[/red]: {key} is not set in .env")
        sys.exit(1)
    return v


def _network_config(network: str) -> dict:
    """Resolve network config: rpc_url + contract addresses."""
    cfg_paths = [
        Path("litnup.toml"),
        Path(__file__).parent.parent / "litnup.toml",
    ]
    # For now we use env-var conventions; litnup.toml support is roadmap
    presets = {
        "base-sepolia": {
            "rpc_url": os.getenv("BASE_SEPOLIA_RPC_URL", "https://sepolia.base.org"),
            "chain_id": 84532,
        },
        "base": {
            "rpc_url": os.getenv("BASE_RPC_URL", "https://mainnet.base.org"),
            "chain_id": 8453,
        },
        "local": {
            "rpc_url": os.getenv("LOCAL_RPC_URL", "http://localhost:8545"),
            "chain_id": 31337,
        },
    }
    if network not in presets:
        CONSOLE.print(f"[red]error[/red]: unknown network {network!r}")
        sys.exit(1)
    return presets[network]


def _print_banner():
    CONSOLE.print(Panel.fit(
        "[bold cyan]LITNUP CLI[/bold cyan] · operator tooling\n"
        f"version {_get_version()} · network: {os.getenv('NETWORK', 'base-sepolia')}",
        border_style="cyan",
    ))


def _get_version() -> str:
    try:
        from . import __version__
        return __version__
    except Exception:
        return "0.1.0"


# ===========================================================================
# CLI root
# ===========================================================================

@click.group()
@click.option("--env", "env_path", type=click.Path(exists=False), default=None,
              help="Path to .env file (defaults to ./.env)")
@click.option("--network", default=None,
              help="Network: base-sepolia | base | local (overrides .env)")
@click.option("--quiet", is_flag=True, help="Suppress banner")
@click.pass_context
def cli(ctx, env_path, network, quiet):
    """LITNUP operator CLI."""
    _load_env(env_path)
    if network:
        os.environ["NETWORK"] = network
    if not quiet and ctx.invoked_subcommand:
        _print_banner()
    ctx.ensure_object(dict)
    ctx.obj["network"] = os.getenv("NETWORK", "base-sepolia")


@cli.command()
def version():
    """Show CLI version."""
    CONSOLE.print(_get_version())


# ===========================================================================
# init — scaffold a new operator repo
# ===========================================================================

@cli.command()
@click.option("--dir", "target_dir", default=".", help="Where to scaffold")
@click.option("--strategy", default="momentum",
              type=click.Choice(["momentum", "meanrev", "basis", "volcarry", "statarb",
                                 "fundingarb", "pairs", "options"]))
def init(target_dir, strategy):
    """Scaffold a new operator working directory.

    Creates:
      .env.example       Environment template
      litnup.toml   Operator config
      strategies/        Custom strategy directory
      logs/              Run logs (gitignored)
      .gitignore
    """
    base = Path(target_dir).resolve()
    base.mkdir(parents=True, exist_ok=True)

    files = {
        ".env.example": _ENV_TEMPLATE,
        "litnup.toml": _TOML_TEMPLATE.format(strategy=strategy),
        ".gitignore": _GITIGNORE,
        "strategies/.gitkeep": "",
        "logs/.gitkeep": "",
    }
    for path, content in files.items():
        full = base / path
        full.parent.mkdir(parents=True, exist_ok=True)
        if full.exists():
            CONSOLE.print(f"  [yellow]skip[/yellow] {path} (exists)")
            continue
        full.write_text(content)
        CONSOLE.print(f"  [green]created[/green] {path}")

    CONSOLE.print(Panel(
        "[green]Scaffolded.[/green]\n\n"
        "Next steps:\n"
        f"  1. cd {target_dir}\n"
        "  2. cp .env.example .env  (and fill in values)\n"
        "  3. litnup-cli paper-trade --strategy momentum --asset BTC --duration 1h\n",
        title="ready",
        border_style="green",
    ))


# ===========================================================================
# config — show / validate
# ===========================================================================

@cli.group()
def config():
    """Show / validate operator configuration."""


@config.command("show")
@click.pass_context
def config_show(ctx):
    """Print loaded configuration with secrets masked."""
    net = ctx.obj["network"]
    cfg = _network_config(net)
    table = Table(title="Configuration", box=box.ROUNDED)
    table.add_column("Key", style="cyan")
    table.add_column("Value", style="white")

    table.add_row("network", net)
    table.add_row("rpc_url", cfg["rpc_url"])
    table.add_row("chain_id", str(cfg["chain_id"]))
    table.add_row("OPERATOR_PRIVATE_KEY", _mask(os.getenv("OPERATOR_PRIVATE_KEY", "")))
    table.add_row("ORACLE_SIGNER_KEY", _mask(os.getenv("ORACLE_SIGNER_KEY", "")))
    table.add_row("AGENT_REGISTRY", os.getenv("AGENT_REGISTRY", "(unset)"))
    table.add_row("STAKING_VAULT", os.getenv("STAKING_VAULT", "(unset)"))
    table.add_row("PERFORMANCE_ORACLE", os.getenv("PERFORMANCE_ORACLE", "(unset)"))
    CONSOLE.print(table)


@config.command("validate")
@click.pass_context
def config_validate(ctx):
    """Check that required env vars are set."""
    required = ["OPERATOR_PRIVATE_KEY", "AGENT_REGISTRY", "STAKING_VAULT"]
    optional = ["ORACLE_SIGNER_KEY", "PERFORMANCE_ORACLE"]
    missing = [k for k in required if not os.getenv(k)]
    table = Table(title="Validation", box=box.ROUNDED)
    table.add_column("Variable")
    table.add_column("Status")
    for k in required:
        ok = "[green]✓[/green]" if os.getenv(k) else "[red]MISSING[/red]"
        table.add_row(k, ok)
    for k in optional:
        ok = "[green]✓[/green]" if os.getenv(k) else "[yellow]optional[/yellow]"
        table.add_row(k, ok)
    CONSOLE.print(table)
    if missing:
        sys.exit(1)


def _mask(s: str) -> str:
    if not s:
        return "(unset)"
    if len(s) <= 8:
        return "***"
    return s[:4] + "…" + s[-4:]


# ===========================================================================
# paper-trade — wraps existing paper_trade module
# ===========================================================================

@cli.command("paper-trade")
@click.option("--strategy", required=True,
              type=click.Choice(["momentum", "meanrev"]))
@click.option("--asset", default="BTC")
@click.option("--duration", default="1h", help="e.g. 30m, 1h, 1d")
@click.option("--interval", default="30s")
@click.option("--initial-equity", default=10_000.0)
def paper_trade(strategy, asset, duration, interval, initial_equity):
    """Run a paper-trading session and print live table."""
    # Defer import so import time stays low
    from .paper_trade import run_paper_trade
    try:
        run_paper_trade(strategy, asset, duration, interval, initial_equity)
    except Exception as e:
        CONSOLE.print(f"[red]error[/red]: {e}")
        sys.exit(1)


# ===========================================================================
# backtest
# ===========================================================================

@cli.command()
@click.option("--strategy", required=True,
              type=click.Choice(["momentum", "meanrev"]))
@click.option("--asset", default="BTC")
@click.option("--start", default=None, help="YYYY-MM-DD; defaults to 90d ago")
@click.option("--end", default=None, help="YYYY-MM-DD; defaults to today")
@click.option("--initial-equity", default=10_000.0)
@click.option("--prices-csv", default=None, type=click.Path(exists=False),
              help="CSV path with columns 'timestamp,price'. If omitted, uses synthetic GBM.")
@click.option("--report-dir", default="./logs", help="Where to write JSON + CSV reports")
def backtest(strategy, asset, start, end, initial_equity, prices_csv, report_dir):
    """Run a backtest over historical price data."""
    if not start:
        start = (datetime.utcnow() - timedelta(days=90)).strftime("%Y-%m-%d")
    if not end:
        end = datetime.utcnow().strftime("%Y-%m-%d")
    CONSOLE.print(f"backtesting [bold]{strategy}[/bold] on [bold]{asset}[/bold] from {start} to {end}")

    try:
        from .backtest import cli_run, write_report
        result = cli_run(
            strategy_name=strategy, asset=asset, start=start, end=end,
            initial_equity=initial_equity, prices_csv=prices_csv,
        )
    except Exception as e:
        CONSOLE.print(f"[red]error[/red]: {e}")
        sys.exit(1)

    summary = result.summary()
    table = Table(title=f"Backtest summary · {strategy} / {asset}", box=box.ROUNDED)
    table.add_column("Metric", style="cyan")
    table.add_column("Value", justify="right")
    for k, v in summary.items():
        table.add_row(k.replace("_", " "), str(v))
    CONSOLE.print(table)

    try:
        path = write_report(result, report_dir)
        CONSOLE.print(f"[green]Report saved:[/green] {path}")
    except Exception as e:
        CONSOLE.print(f"[yellow]Report write failed[/yellow]: {e}")


# ===========================================================================
# enroll
# ===========================================================================

@cli.command()
@click.option("--bond", required=True, type=float, help="Bond amount in $LITNUP (e.g. 50000)")
@click.option("--metadata-uri", required=True,
              help="IPFS URI to operator metadata JSON")
@click.option("--protocol-fee-bps", default=200, type=int,
              help="Protocol fee in bps (default 2%)")
@click.option("--dry-run", is_flag=True)
@click.pass_context
def enroll(ctx, bond, metadata_uri, protocol_fee_bps, dry_run):
    """Enroll the configured operator with the AgentRegistry."""
    _require_env("OPERATOR_PRIVATE_KEY")
    _require_env("AGENT_REGISTRY")
    if dry_run:
        CONSOLE.print(Panel.fit(
            f"[yellow]DRY RUN[/yellow]\n"
            f"  bond:           {bond} AGENTIC\n"
            f"  metadata URI:   {metadata_uri}\n"
            f"  fee bps:        {protocol_fee_bps}\n"
            f"  registry:       {os.getenv('AGENT_REGISTRY')}\n"
            "  no transaction broadcast"
        ))
        return

    CONSOLE.print("[yellow]note[/yellow]: live enroll requires the operator to have approved "
                  "the AgentRegistry to spend $LITNUP. Run `litnup-cli token approve` first.")
    CONSOLE.print("[red]not yet implemented[/red] — the enroll() web3 call will land in v0.2; "
                  "for now use the public Foundry script.")


# ===========================================================================
# oracle commands
# ===========================================================================

@cli.group()
def oracle():
    """Oracle signer operations."""


@oracle.command("sign")
@click.option("--agent-id", required=True, type=int)
@click.option("--epoch", required=True, type=int)
@click.option("--pnl-delta", required=True, type=int,
              help="PnL delta in 1e18 token units (signed; reputation/fee basis)")
@click.option("--fee-amount", default=0, type=int,
              help="Performance fee in reward-token base units (e.g. USDC 1e6)")
@click.option("--to-buyback-bps", default=5000, type=int)
@click.option("--fee-payer", default=lambda: os.getenv("FEE_PAYER_ADDRESS", "0x" + "0" * 40),
              help="Operator address that approved the vault to pull the fee")
@click.option("--chain-id", default=lambda: int(os.getenv("CHAIN_ID", "84532")), type=int)
@click.option("--oracle-address", default=lambda: os.getenv("PERFORMANCE_ORACLE_ADDRESS", "0x" + "0" * 40))
@click.option("--deadline-secs", default=21600, type=int,
              help="Seconds-from-now until signature deadline (default 6h to outlast quorum gathering)")
def oracle_sign(agent_id, epoch, pnl_delta, fee_amount, to_buyback_bps, fee_payer,
                chain_id, oracle_address, deadline_secs):
    """Produce an EIP-712 signature for an attestation (matches PerformanceOracle.ATTESTATION_TYPEHASH)."""
    _require_env("ORACLE_SIGNER_KEY")
    try:
        from .oracle_signer import Attestation, sign_attestation
        att = Attestation(
            agent_id=agent_id,
            pnl_delta_wei=pnl_delta,
            fee_amount=fee_amount,
            to_buyback_bps=to_buyback_bps,
            fee_payer=fee_payer,
            epoch=epoch,
            deadline=int(time.time()) + deadline_secs,
        )
        sig = sign_attestation(att, os.getenv("ORACLE_SIGNER_KEY"), chain_id, oracle_address)
        CONSOLE.print(Panel(
            f"[green]signed[/green] by {sig['signer']}\n\n"
            f"agent_id:        {agent_id}\n"
            f"epoch:           {epoch}\n"
            f"pnl_delta:       {pnl_delta}\n"
            f"fee_amount:      {fee_amount}\n"
            f"to_buyback_bps:  {to_buyback_bps}\n"
            f"fee_payer:       {fee_payer}\n"
            f"deadline:        {att.deadline}\n"
            f"signature:       {sig['signature']}\n",
            title="EIP-712 attestation",
            border_style="green",
        ))
    except Exception as e:
        CONSOLE.print(f"[red]error[/red]: {e}")
        sys.exit(1)


@oracle.command("status")
def oracle_status():
    """Print local oracle signer's address + recent activity."""
    key = os.getenv("ORACLE_SIGNER_KEY")
    if not key:
        CONSOLE.print("[red]ORACLE_SIGNER_KEY not set[/red]")
        sys.exit(1)
    try:
        from eth_account import Account
        addr = Account.from_key(key).address
        CONSOLE.print(f"signer address: [cyan]{addr}[/cyan]")
    except Exception as e:
        CONSOLE.print(f"[red]error[/red]: {e}")


# ===========================================================================
# vault commands
# ===========================================================================

@cli.group()
def vault():
    """Read vault state."""


@vault.command("status")
@click.option("--agent-id", required=True, type=int)
@click.pass_context
def vault_status(ctx, agent_id):
    """Show the vault state for a given agent."""
    _require_env("STAKING_VAULT")
    try:
        from web3 import Web3
        cfg = _network_config(ctx.obj["network"])
        w3 = Web3(Web3.HTTPProvider(cfg["rpc_url"]))
        if not w3.is_connected():
            CONSOLE.print("[red]error[/red]: cannot connect to RPC")
            sys.exit(1)
        # Minimal ABI to read vaults() tuple
        abi = [{
            "type": "function",
            "name": "vaults",
            "stateMutability": "view",
            "inputs": [{"name": "agentId", "type": "uint256"}],
            "outputs": [
                {"name": "totalAssets", "type": "uint128"},
                {"name": "totalShares", "type": "uint128"},
                {"name": "lastAttestation", "type": "uint64"},
                {"name": "cooldown", "type": "uint64"},
            ],
        }]
        addr = Web3.to_checksum_address(os.getenv("STAKING_VAULT"))
        contract = w3.eth.contract(address=addr, abi=abi)
        total_assets, total_shares, last_atts, cooldown = contract.functions.vaults(agent_id).call()
        table = Table(title=f"Vault · agent #{agent_id}", box=box.ROUNDED)
        table.add_column("Field")
        table.add_column("Value")
        table.add_row("Total Assets", f"{total_assets / 1e18:,.4f} AGENTIC")
        table.add_row("Total Shares", f"{total_shares / 1e18:,.4f}")
        sp = total_assets / total_shares if total_shares > 0 else 1.0
        table.add_row("Share Price", f"{sp:.6f}")
        table.add_row("Last Attestation", str(datetime.utcfromtimestamp(last_atts)) if last_atts else "never")
        table.add_row("Cooldown", f"{cooldown}s ({cooldown / 86400:.1f}d)")
        CONSOLE.print(table)
    except Exception as e:
        CONSOLE.print(f"[red]error[/red]: {e}")
        sys.exit(1)


# ===========================================================================
# operator commands
# ===========================================================================

@cli.group()
def operator():
    """Operator-level utilities."""


@operator.command("stats")
def operator_stats():
    """Show local operator's enrollment + activity stats."""
    pk = os.getenv("OPERATOR_PRIVATE_KEY")
    if not pk:
        CONSOLE.print("[red]OPERATOR_PRIVATE_KEY not set[/red]")
        sys.exit(1)
    try:
        from eth_account import Account
        addr = Account.from_key(pk).address
        CONSOLE.print(f"operator address: [cyan]{addr}[/cyan]")
        CONSOLE.print("[yellow]note[/yellow]: deeper enrollment / TVL views ship in v0.2")
    except Exception as e:
        CONSOLE.print(f"[red]error[/red]: {e}")


# ===========================================================================
# monitor — wraps monitor.py
# ===========================================================================

@cli.command()
@click.option("--agent-id", required=True, type=int)
@click.option("--interval", default=10, help="Refresh seconds")
def monitor(agent_id, interval):
    """Live-tail oracle attestations + vault state for an agent."""
    try:
        from .monitor import run_monitor
        run_monitor(agent_id=agent_id, interval=interval)
    except Exception as e:
        CONSOLE.print(f"[red]error[/red]: {e}")
        sys.exit(1)


# ===========================================================================
# Templates
# ===========================================================================

_ENV_TEMPLATE = """\
# LITNUP operator environment
# Fill in real values; never commit this file.

NETWORK=base-sepolia
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
# BASE_RPC_URL=https://mainnet.base.org

# Operator wallet (the address that enrolled the agent)
OPERATOR_PRIVATE_KEY=

# Oracle signer key (only set if you're an oracle co-signer)
ORACLE_SIGNER_KEY=

# Contract addresses (deploy outputs)
AGENT_REGISTRY=
STAKING_VAULT=
PERFORMANCE_ORACLE=
BUYBACK_BURN=

# Strategy config
STRATEGY=momentum
ASSET=BTC
"""

_TOML_TEMPLATE = """\
# litnup.toml — operator config
[operator]
name = ""
strategy = "{strategy}"

[strategy]
asset = "BTC"
fast = 12
slow = 48

[risk]
max_drawdown_pct = 20
position_cap_pct = 50

[telemetry]
log_dir = "logs"
attestation_interval_secs = 14400
"""

_GITIGNORE = """\
.env
__pycache__/
*.pyc
logs/
.coverage
.pytest_cache/
"""


# ===========================================================================
# Entrypoint
# ===========================================================================

def main():
    cli(obj={})


if __name__ == "__main__":
    main()
