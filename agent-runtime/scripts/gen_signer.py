"""Generate a fresh signer keypair for testing. Writes private key to .env.

DO NOT use this key for anything other than testing on Base Sepolia.
For mainnet, use a hardware-key-backed signer.
"""
from __future__ import annotations

import os
from pathlib import Path
from eth_account import Account


def main():
    Account.enable_unaudited_hdwallet_features()
    acct, mnemonic = Account.create_with_mnemonic()
    print("Generated signer:")
    print(f"  Address:  {acct.address}")
    print(f"  Private:  {acct.key.hex()}")
    print()
    print("Mnemonic (back this up offline if needed):")
    print(f"  {mnemonic}")
    print()

    env_path = Path(".env")
    if env_path.exists():
        existing = env_path.read_text()
        if "ORACLE_SIGNER_PRIVATE_KEY" in existing:
            print(".env already has ORACLE_SIGNER_PRIVATE_KEY — not overwriting.")
            print("Edit manually if you want to replace.")
            return
        with env_path.open("a") as f:
            f.write(f"\nORACLE_SIGNER_PRIVATE_KEY={acct.key.hex()}\n")
    else:
        env_path.write_text(f"ORACLE_SIGNER_PRIVATE_KEY={acct.key.hex()}\n")
    print(f"Wrote ORACLE_SIGNER_PRIVATE_KEY to .env")


if __name__ == "__main__":
    main()
