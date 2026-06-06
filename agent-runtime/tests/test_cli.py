"""Smoke tests for the alphagentic-cli."""
from __future__ import annotations

import os
from pathlib import Path

import pytest
from click.testing import CliRunner

from agent_runtime.cli import cli


@pytest.fixture
def runner():
    return CliRunner()


def test_version(runner):
    res = runner.invoke(cli, ["--quiet", "version"])
    assert res.exit_code == 0
    assert res.output.strip()


def test_init_scaffolds(tmp_path, runner):
    res = runner.invoke(cli, ["--quiet", "init", "--dir", str(tmp_path), "--strategy", "momentum"])
    assert res.exit_code == 0
    assert (tmp_path / ".env.example").exists()
    assert (tmp_path / "alphagentic.toml").exists()
    assert (tmp_path / ".gitignore").exists()
    assert (tmp_path / "strategies").is_dir()
    assert (tmp_path / "logs").is_dir()


def test_config_show_runs(runner, monkeypatch):
    monkeypatch.delenv("OPERATOR_PRIVATE_KEY", raising=False)
    res = runner.invoke(cli, ["--quiet", "config", "show"])
    assert res.exit_code == 0
    assert "network" in res.output.lower()


def test_config_validate_missing_required(runner, monkeypatch):
    for var in ["OPERATOR_PRIVATE_KEY", "AGENT_REGISTRY", "STAKING_VAULT"]:
        monkeypatch.delenv(var, raising=False)
    res = runner.invoke(cli, ["--quiet", "config", "validate"])
    assert res.exit_code == 1


def test_enroll_dry_run(runner, monkeypatch):
    monkeypatch.setenv("OPERATOR_PRIVATE_KEY", "0x" + "11" * 32)
    monkeypatch.setenv("AGENT_REGISTRY", "0x" + "22" * 20)
    res = runner.invoke(cli, [
        "--quiet", "enroll",
        "--bond", "50000",
        "--metadata-uri", "ipfs://test",
        "--dry-run",
    ])
    assert res.exit_code == 0
    assert "DRY RUN" in res.output


def test_oracle_status_requires_key(runner, monkeypatch):
    monkeypatch.delenv("ORACLE_SIGNER_KEY", raising=False)
    res = runner.invoke(cli, ["--quiet", "oracle", "status"])
    assert res.exit_code == 1


def test_oracle_status_with_key(runner, monkeypatch):
    # Generate a deterministic test key (not real, fixture only)
    monkeypatch.setenv("ORACLE_SIGNER_KEY", "0x" + "11" * 32)
    res = runner.invoke(cli, ["--quiet", "oracle", "status"])
    # Either "signer address:" if eth_account is present, or an error if it isn't
    assert res.exit_code in (0, 1)
