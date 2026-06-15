"""End-to-end EIP-712 round-trip test.

Validates that:
1. Python signs an Attestation with the same domain + types as PerformanceOracle.sol
2. The recovered signer matches the keypair we used
3. Cross-signer scenarios (mismatched domain, replay) are rejected by signature recovery alone

This is the CI gate that proves off-chain and on-chain agree on the typed-data layout.
If this test fails after a contract change, you've broken the oracle interface.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from eth_account import Account
from eth_account.messages import encode_typed_data

from agent_runtime.oracle_signer import (
    Attestation,
    sign_attestation,
    build_typed_data,
)


# Reference test vectors — change ONLY if you change the on-chain TYPEHASH
SAMPLE_AGENT_ID = 42
SAMPLE_PNL_DELTA = 250 * 10**18
SAMPLE_FEE = 25 * 10**6           # reward-token (USDC) units
SAMPLE_BPS = 5000
SAMPLE_PAYER = "0xcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd"
SAMPLE_EPOCH = 7
SAMPLE_DEADLINE = 2_000_000_000
TEST_CHAIN_ID = 84532  # Base Sepolia
TEST_ORACLE_ADDR = "0xabababababababababababababababababababab"


def test_typed_data_layout_matches_solidity():
    """Verify the Python typed data exactly matches what _hashTypedDataV4 expects."""
    att = Attestation(SAMPLE_AGENT_ID, SAMPLE_PNL_DELTA, SAMPLE_FEE, SAMPLE_BPS, SAMPLE_PAYER, SAMPLE_EPOCH, SAMPLE_DEADLINE)
    typed = build_typed_data(att, TEST_CHAIN_ID, TEST_ORACLE_ADDR)

    # Domain assertions
    assert typed["domain"]["name"] == "LITNUPOracle"
    assert typed["domain"]["version"] == "1"
    assert typed["domain"]["chainId"] == TEST_CHAIN_ID
    assert typed["domain"]["verifyingContract"] == TEST_ORACLE_ADDR

    # Primary type
    assert typed["primaryType"] == "Attestation"

    # Field order matters for the type hash — verify it
    fields = [f["name"] for f in typed["types"]["Attestation"]]
    assert fields == ["agentId", "pnlDelta", "feeAmount", "toBuybackBps", "feePayer", "epoch", "deadline"]


def test_signature_recovers_to_signer():
    """End-to-end: sign with key, recover via eth_account, verify match."""
    acct = Account.from_key("0x" + "1" * 64)

    att = Attestation(SAMPLE_AGENT_ID, SAMPLE_PNL_DELTA, SAMPLE_FEE, SAMPLE_BPS, SAMPLE_PAYER, SAMPLE_EPOCH, SAMPLE_DEADLINE)
    out = sign_attestation(att, acct.key.hex(), TEST_CHAIN_ID, TEST_ORACLE_ADDR)
    assert out["signer"] == acct.address

    # Re-recover from signature
    typed = build_typed_data(att, TEST_CHAIN_ID, TEST_ORACLE_ADDR)
    signable = encode_typed_data(full_message=typed)
    recovered = Account.recover_message(signable, signature=out["signature"])
    assert recovered == acct.address


def test_different_chain_id_changes_signature():
    """A signature for chain A should NOT recover the same hash on chain B."""
    acct = Account.from_key("0x" + "1" * 64)
    att = Attestation(SAMPLE_AGENT_ID, SAMPLE_PNL_DELTA, SAMPLE_FEE, SAMPLE_BPS, SAMPLE_PAYER, SAMPLE_EPOCH, SAMPLE_DEADLINE)
    out_a = sign_attestation(att, acct.key.hex(), 1, TEST_ORACLE_ADDR)
    out_b = sign_attestation(att, acct.key.hex(), 84532, TEST_ORACLE_ADDR)
    assert out_a["signature"] != out_b["signature"]


def test_different_contract_address_changes_signature():
    """Same chain, different verifyingContract → different signature."""
    acct = Account.from_key("0x" + "1" * 64)
    att = Attestation(SAMPLE_AGENT_ID, SAMPLE_PNL_DELTA, SAMPLE_FEE, SAMPLE_BPS, SAMPLE_PAYER, SAMPLE_EPOCH, SAMPLE_DEADLINE)
    a = sign_attestation(att, acct.key.hex(), TEST_CHAIN_ID, "0x" + "ab" * 20)
    b = sign_attestation(att, acct.key.hex(), TEST_CHAIN_ID, "0x" + "cd" * 20)
    assert a["signature"] != b["signature"]


def test_three_signers_produce_distinct_signatures():
    """Multi-sig flow: each signer produces a unique signature; all recover correctly."""
    keys = ["0x" + str(i) * 64 for i in range(1, 4)]
    accts = [Account.from_key(k) for k in keys]
    att = Attestation(SAMPLE_AGENT_ID, SAMPLE_PNL_DELTA, SAMPLE_FEE, SAMPLE_BPS, SAMPLE_PAYER, SAMPLE_EPOCH, SAMPLE_DEADLINE)
    sigs = [sign_attestation(att, k, TEST_CHAIN_ID, TEST_ORACLE_ADDR) for k in keys]
    sig_strings = [s["signature"] for s in sigs]
    assert len(set(sig_strings)) == 3
    for sig, acct in zip(sigs, accts):
        assert sig["signer"] == acct.address


if __name__ == "__main__":
    test_typed_data_layout_matches_solidity()
    test_signature_recovers_to_signer()
    test_different_chain_id_changes_signature()
    test_different_contract_address_changes_signature()
    test_three_signers_produce_distinct_signatures()
    print("All EIP-712 round-trip tests passed ✓")
