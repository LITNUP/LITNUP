# Security Policy

## Supported versions

| Component | Version | Status |
|---|---|---|
| Smart contracts | testnet (Base Sepolia) | ⚠️ Pre-audit. Do not use real funds. |
| Smart contracts | mainnet | TBD — not yet deployed |
| Agent runtime | 0.1.x | Active |

## Reporting a vulnerability

**Do NOT open a public issue for security vulnerabilities.**

### Preferred channels (in order)

1. **Immunefi bounty** (when live): https://immunefi.com/bounty/litnup
2. **Email**: `security@litnup.xyz` (PGP key below)
3. **Direct to founders**: DM `@LITNUP` on X with a request for a private channel

### What to include

- A description of the issue
- Steps to reproduce
- Affected component and commit hash
- Your assessment of severity
- (Optional) suggested mitigation

### Our commitment

- We acknowledge receipt within **48 hours**
- We provide an initial severity assessment within **5 business days**
- We resolve **Critical** issues within **14 days** (with a tested fix + post-mortem)
- We coordinate disclosure with the reporter

## Severity scale

| Severity | Examples | Bounty range (post-Immunefi launch) |
|---|---|---|
| Critical | Drain of funds; permanent loss of stake; arbitrary minting | $50,000 – $500,000 |
| High | Theft of fees; bypass of slashing; oracle bypass | $10,000 – $50,000 |
| Medium | Rounding losses > 1%; griefing of operators | $2,000 – $10,000 |
| Low | UI inconsistencies; minor griefing; gas-related issues | $200 – $2,000 |
| Informational | Best-practice violations; doc errors | Public credit, swag |

Pre-Immunefi-launch, payouts are negotiated case-by-case at our discretion.

## Out of scope

- Issues in third-party dependencies (OpenZeppelin, eth_account, etc.) — report upstream
- Theoretical issues without proof of exploit
- DoS via excessive gas (we have caps; reach out if you find one)
- Spam / phishing of unrelated services using our brand

## Hall of fame

When we have valid disclosures, we'll list them here (with reporter consent).

## PGP

```
-----BEGIN PGP PUBLIC KEY BLOCK-----
[ Replace this block with your real PGP public key. Generate via:
  gpg --gen-key, then gpg --armor --export security@litnup.xyz ]
-----END PGP PUBLIC KEY BLOCK-----
```

---

## Self-disclosed limitations

Things we already know about and don't need re-reported:

- **Multi-sig oracle is a centralization vector.** v1 is 5-of-7; we are migrating to 13-of-21 then to ZK-proof attestations in v2. This is documented in the litepaper.
- **PaperVenue is paper.** Of course it is.
- **No insurance fund yet.** Will be seeded post-mainnet from fees.
- **HyperliquidVenue is a STUB.** It will not place real orders. The signing flow requires implementation before live use, behind explicit env-var opt-in.
- **No production deployment script.** `deploy/Deploy.s.sol` is testnet-only; mainnet requires a multisig deployer and a more careful deploy script.

---

If something feels wrong, write to us. We'd rather over-react to a false alarm than under-react to a real one.
