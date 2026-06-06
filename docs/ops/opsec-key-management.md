# Opsec & Key Management

**Status:** Draft v1 · last updated 2026-05-09
**Audience:** Foundation board, multisig signers, core contributors, security advisors
**License:** Internal — share excerpts only with prior board approval

---

## Threat model

We assume a sophisticated attacker who:

- Has read every public artifact (code, docs, blog, AMA transcripts)
- Has already compromised at least one team member's email or browser session
- Will spend $10K-$100K on a targeted phishing campaign with our team as the bullseye
- Will attempt physical-attack vectors on signers (luggage theft, $5 wrench attack)
- Has access to nation-state-level resources for at least one attempt
- Will try social-engineering against KYC providers, custodians, and CEXs we use

We do NOT assume:
- The attacker has compromised hardware-wallet firmware (assume Ledger/Trezor are sound)
- The attacker has compromised Base sequencer
- The attacker has compromised OpenZeppelin / audited contract code at the silent supply-chain level

---

## Key categories & custody

Every cryptographic key in the protocol fits one of these categories:

### Category A — Foundation Treasury (5-of-9 cold)
Holds: most of the foundation's $LITNUP, USDC, ETH, BTC reserves
- Hardware: Ledger Nano X or Plus, fresh-from-manufacturer, sealed shipping verified
- 9 distinct individuals across 9 distinct jurisdictions
- Each signer keeps:
  - Hardware wallet in geographically separate location from where they live
  - 24-word seed phrase split via Shamir Secret Sharing 3-of-5 across trusted parties (NOT all the same trusted parties for different signers)
  - At least one shard in a bank safety deposit box
  - One shard with a legal trustee bound by NDA + foundation indemnification
  - One shard at a separate residence
- Signing requires physical presence with hardware wallet (no signing via USB extension or laptop hot-storage of devices)

### Category B — Operational Multisig (3-of-5 hot)
Holds: enough working capital for one quarter of operations (~$1M USDC)
- Hardware: Ledger Nano S Plus, sealed shipping verified
- 5 individuals, all foundation employees or trusted operators
- Seed phrases held by signers + one shard with foundation legal counsel
- Used daily; on hardware wallets only — never paper, never browser-imported

### Category C — Oracle Signers (3-of-5 hot, automated)
Holds: signing key for `applyAttestation` calls; no fund custody
- Hardware: AWS Nitro Enclaves on three different cloud providers (AWS, GCP, Azure)
- Plus 2 hardware-key signers as physical-presence backup
- Keys generated inside enclave; never exported
- Enclave attestations published quarterly to verify code integrity
- 4-hour cycle = signers can rotate every 24 hours without operational impact

### Category D — PauseGuardian Signers (3-of-5 hot)
Holds: signing key for emergency pause actions; no fund custody
- Hardware: Ledger Nano X or YubiKey FIDO2
- 5 individuals: 2 foundation board, 2 outside security advisors, 1 community-elected
- Each maintains a 24/7 on-call rotation schedule
- One signer must be reachable within 30 minutes for the guardian to be effective

### Category E — Founder / Team Operational Wallets
Holds: vested team tokens, personal operational ETH/USDC
- Hardware: individual choice (Ledger / Trezor / hardware-secured macOS keychain)
- Treated as personal property of the recipient; foundation does not custody
- Recipients sign a Reasonable Care Affidavit acknowledging they're responsible for security

### Category F — Vesting & Schedule Beneficiary Wallets
Holds: vesting beneficiary addresses; receives vested tokens
- Hardware: per-recipient choice
- We strongly recommend a hardware wallet, ideally separate from the recipient's daily-use wallet
- Address change procedure: requires 7-day delay + foundation legal notarization

### Category G — Public Communications Keys
Holds: GitHub commit signing, Twitter/X account, Discord admin, email accounts
- Hardware: YubiKey for all account access where supported
- 2FA: hardware-only, no SMS, no authenticator-app fallback
- Recovery codes: split via Shamir 2-of-3 across trustees + safe deposit box
- Account access requires both individual login + foundation-board authorization for any "official statement" post

---

## Hardware wallet protocol

For every hardware wallet purchase:

1. Buy directly from manufacturer (Ledger.com / Trezor.io). Never Amazon, never resellers.
2. Inspect packaging tape on arrival; reject if anti-tamper evidence is broken
3. Initialize device offline with no internet connection during seed generation
4. Generate seed phrase on the device itself; never on a computer screen
5. Verify seed phrase by writing on supplied recovery card (or equivalent)
6. Test seed by deleting device + restoring from seed before any funds touch the wallet
7. Verify firmware version against manufacturer's current release; if any flag, replace device

---

## Seed phrase storage

For signers in Category A and B:

- Seed phrases NEVER typed into a digital device after initialization
- Stored on:
  - Acid-resistant metal plates (Cobo Tablet, Cryptosteel, or comparable)
  - Stamped or engraved letters; no marker pen (fades)
  - Stored in waterproof + fireproof safe
- Never stored:
  - On any computer (including encrypted disk image)
  - In any cloud (including encrypted)
  - In any password manager (including 1Password / Bitwarden)
  - In any photo or scan
  - On any printed paper unless the paper is in safe deposit and treated as Tier 1

---

## Signing ceremony protocols

For Category A (Foundation Treasury) transactions:

1. **Pre-ceremony:**
   - Transaction details published in foundation-board-only channel 24h before
   - Each signer independently verifies destination + amount + reason from public source (e.g., approved budget)
   - Signers physically retrieve hardware wallet from cold location

2. **Ceremony:**
   - At least 5 signers physically present (in person or video call with positive verbal verification)
   - Each signer reads aloud the destination address from their hardware wallet display
   - Each signer reads aloud the amount from their hardware wallet display
   - Verbal confirmation across all signers that the values match
   - Each signer presses the "Approve" button on hardware

3. **Post-ceremony:**
   - Transaction broadcast
   - Confirmation logged in foundation operational system
   - Public disclosure on next quarterly report

---

## Phishing & social engineering defenses

- **No surprise communications.** Any urgent request to move funds gets ignored if it didn't come through pre-established channels with pre-established time delays.
- **Out-of-band verification.** Any large transaction request received via Signal/Discord/email is verified via voice call to a pre-established number.
- **No DMs from "team members."** Founder will never DM individual signers asking them to sign anything urgent. If you receive such a DM, it's a fake.
- **Calendar invites are not authentication.** A calendar invite from a recognizable email address is not authentication. Voice or video confirmation is required.
- **Hardware key for everything.** Email, GitHub, Twitter, Discord — all use FIDO2 hardware keys. SMS 2FA is forbidden.

---

## Repository security

- All commits to `main` branch must be:
  - Signed by a developer's GPG key registered with GitHub
  - Reviewed by at least one other contributor
  - Pass CI checks
- Branch protection enforced for `main` (no force pushes, no admin override)
- Sensitive directories (`contracts/src`, `deploy/`, `agent-runtime/security`) require code-owner review
- Secrets never committed; `.env.example` only; pre-commit hook scans for keys
- `npm audit` / `pip-audit` run in CI weekly; high-severity findings block merges

---

## Wallet hygiene rules

For everyone touching a project wallet:

- Use a dedicated browser profile for crypto activity; never the same profile as personal browsing
- No unsanctioned browser extensions on that profile
- Connect wallets only to known, bookmarked URLs
- Verify URLs character-by-character before signing any transaction
- Reject any signing request that:
  - Asks for permission scope you don't recognize
  - Has unfamiliar smart-contract addresses
  - Has a token amount that doesn't match what you expected
  - Has a destination address that doesn't match what you intend
- Use a dedicated "burn" wallet (with no real funds) to test new contracts before signing with real wallet
- Hardware wallet display IS the source of truth, NOT what your laptop shows

---

## Incident response triggers

The following events automatically trigger an incident response (see `incident-runbook.md`):

- Any signer reports a suspected device compromise
- Any signer reports a successful phishing attempt that may have exposed credentials
- Any oracle signer reports an enclave attestation mismatch
- Any unexpected transaction observed on any official wallet
- Any unauthorized access to foundation systems detected
- Any alert from monitoring systems (Tenderly, Forta, OpenZeppelin Defender) above severity 3

When triggered, the on-call rotation pages the PauseGuardian signers and the foundation board within 5 minutes.

---

## Geographic and physical operational security

- Signers do not announce signing-ceremony locations on social media
- Signers do not announce travel publicly while carrying signing devices
- Hardware wallets are not transported via checked baggage
- Foundation does not concentrate physical signers at a single conference / event
- Signers do not wear identifying merchandise (foundation-branded clothing) in public when carrying devices
- Backup signer contact is established for every signer in case of incapacity

---

## Personnel security

- All foundation employees + paid contractors:
  - Background-checked at hire (criminal record, sanctions list, employment verification)
  - Sign confidentiality + IP-assignment agreements
  - Comply with this opsec policy as a condition of employment
- Signers are additionally:
  - Identity-verified by a tier-1 KYC provider with biometric verification
  - Provided foundation-funded indemnification for legal exposure stemming from good-faith signing actions
  - Subject to annual security training + tabletop incident exercises

---

## Periodic exercises

- **Monthly:** PauseGuardian on-call rotation drill; verifying response time for at least 3-of-5 within 30 minutes
- **Quarterly:** Foundation multisig signing-ceremony rehearsal with a benign test transaction
- **Quarterly:** Phishing simulation — independent security firm sends targeted phishing to all signers; results published internally
- **Annually:** Full security audit of foundation systems by external firm (rotating firm year-over-year)
- **Annually:** Tabletop incident exercise covering at least 3 distinct scenarios

---

## What we don't do

We deliberately avoid certain practices that look like security but aren't:

- **No "hot wallet for convenience."** Convenience is incompatible with cold custody. If we need fast access to capital, that's the operational multisig (Tier 1), not the foundation cold storage.
- **No "trusted custodian."** We do not use Anchorage, Coinbase Custody, BitGo, Fireblocks, or similar for foundation cold reserves. Counterparty risk concentrates poorly.
- **No "office shared device."** Hardware wallets are not shared. Each signer has their own.
- **No "shared seed phrase."** Even shards are not duplicated unnecessarily.
- **No "signing on the train."** Mobile signing on transit is forbidden for Tier 1+2 transactions.
- **No emergency override.** There is no break-glass procedure that bypasses the multisig threshold. If we lose enough signers to fall below threshold, we accept the lockup — better than a bypass that an attacker could exploit.

---

## Policy revisions

This document is versioned. Revisions require:

- Foundation board majority approval
- Public notice (without revealing specifics that would weaken the policy)
- Diff documented in foundation-internal records

Last revision: 2026-05-09 (initial draft).

— The LITNUP Foundation
