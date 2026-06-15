"""Tests for EIP-712 oracle signer."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from eth_account import Account

from agent_runtime.oracle_signer import Attestation, sign_attestation, build_typed_data


def test_typed_data_structure():
    att = Attestation(agent_id=1, pnl_delta_wei=10**18, fee_amount=10**6, to_buyback_bps=5000, fee_payer="0x"+"ab"*20, epoch=1, deadline=2_000_000_000)
    typed = build_typed_data(att, chain_id=84532, oracle_address="0x" + "ab" * 20)
    assert typed["primaryType"] == "Attestation"
    assert typed["domain"]["name"] == "LITNUPOracle"
    assert typed["domain"]["chainId"] == 84532
    assert typed["message"]["agentId"] == 1
    assert typed["message"]["pnlDelta"] == 10**18


def test_sign_and_recover():
    # Test key (NEVER use in production)
    acct = Account.from_key("0x" + "1" * 64)
    att = Attestation(agent_id=1, pnl_delta_wei=10**18, fee_amount=10**6, to_buyback_bps=5000, fee_payer="0x"+"ab"*20, epoch=1, deadline=2_000_000_000)
    out = sign_attestation(att, acct.key.hex(), chain_id=84532, oracle_address="0x" + "ab" * 20)
    assert out["signer"] == acct.address
    assert "signature" in out
    # Signature is 65 bytes = 130 hex chars + 0x = 132
    assert len(out["signature"]) in (130, 132)


if __name__ == "__main__":
    test_typed_data_structure()
    test_sign_and_recover()
    print("All oracle_signer tests passed ✓")
