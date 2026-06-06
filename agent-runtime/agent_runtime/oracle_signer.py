"""EIP-712 signing for PerformanceOracle attestations.

Matches PerformanceOracle.sol's `ATTESTATION_TYPEHASH`:
  Attestation(uint256 agentId,int256 pnlDelta,uint256 feeOnGross,uint64 epoch,uint64 deadline)

Domain:
  name="LITNUPOracle", version="1", chainId=<dynamic>, verifyingContract=<oracle address>
"""
from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass

from eth_account import Account
from eth_account.messages import encode_typed_data


DOMAIN_NAME = "LITNUPOracle"
DOMAIN_VERSION = "1"


@dataclass
class Attestation:
    agent_id: int
    pnl_delta_wei: int     # signed; positive = profit, scaled to 1e18
    fee_on_gross_wei: int  # unsigned; portion of profit taken as fee
    epoch: int
    deadline: int          # unix seconds


def build_typed_data(att: Attestation, chain_id: int, oracle_address: str) -> dict:
    return {
        "domain": {
            "name": DOMAIN_NAME,
            "version": DOMAIN_VERSION,
            "chainId": chain_id,
            "verifyingContract": oracle_address,
        },
        "types": {
            "EIP712Domain": [
                {"name": "name", "type": "string"},
                {"name": "version", "type": "string"},
                {"name": "chainId", "type": "uint256"},
                {"name": "verifyingContract", "type": "address"},
            ],
            "Attestation": [
                {"name": "agentId", "type": "uint256"},
                {"name": "pnlDelta", "type": "int256"},
                {"name": "feeOnGross", "type": "uint256"},
                {"name": "epoch", "type": "uint64"},
                {"name": "deadline", "type": "uint64"},
            ],
        },
        "primaryType": "Attestation",
        "message": {
            "agentId": att.agent_id,
            "pnlDelta": att.pnl_delta_wei,
            "feeOnGross": att.fee_on_gross_wei,
            "epoch": att.epoch,
            "deadline": att.deadline,
        },
    }


def sign_attestation(att: Attestation, signer_private_key: str, chain_id: int, oracle_address: str) -> dict:
    """Sign an attestation. Returns a dict with signature + payload (for logging / submission).

    The returned signature is 65 bytes hex (r || s || v).
    """
    if not signer_private_key.startswith("0x"):
        signer_private_key = "0x" + signer_private_key
    account = Account.from_key(signer_private_key)

    typed = build_typed_data(att, chain_id, oracle_address)
    signable = encode_typed_data(full_message=typed)
    signed = account.sign_message(signable)

    return {
        "attestation": {
            "agentId": att.agent_id,
            "pnlDelta": str(att.pnl_delta_wei),
            "feeOnGross": str(att.fee_on_gross_wei),
            "epoch": att.epoch,
            "deadline": att.deadline,
        },
        "signer": account.address,
        "signature": signed.signature.hex(),
        "v": signed.v,
        "r": hex(signed.r),
        "s": hex(signed.s),
        "domain": typed["domain"],
        "messageHash": signed.messageHash.hex() if hasattr(signed, "messageHash") else None,
    }


# CLI entry point: `python -m agent_runtime.oracle_signer --agent-id 1 --pnl 250 --epoch 1`
if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--agent-id", type=int, required=True)
    parser.add_argument("--pnl", type=float, required=True, help="PnL delta in $LITNUP tokens (will be scaled to 1e18)")
    parser.add_argument("--fee", type=float, default=0.0, help="Fee on gross PnL (token units)")
    parser.add_argument("--epoch", type=int, required=True)
    parser.add_argument("--deadline-minutes", type=int, default=60)
    parser.add_argument("--chain-id", type=int, default=int(os.getenv("CHAIN_ID", "84532")))
    parser.add_argument("--oracle", default=os.getenv("PERFORMANCE_ORACLE_ADDRESS", "0x0000000000000000000000000000000000000000"))
    parser.add_argument("--key", default=os.getenv("ORACLE_SIGNER_PRIVATE_KEY"))
    args = parser.parse_args()

    if not args.key:
        raise SystemExit("ORACLE_SIGNER_PRIVATE_KEY not set; run scripts/gen_signer.py first.")

    deadline = int(time.time()) + args.deadline_minutes * 60
    att = Attestation(
        agent_id=args.agent_id,
        pnl_delta_wei=int(args.pnl * 1e18),
        fee_on_gross_wei=int(args.fee * 1e18),
        epoch=args.epoch,
        deadline=deadline,
    )
    out = sign_attestation(att, args.key, args.chain_id, args.oracle)
    print(json.dumps(out, indent=2))
