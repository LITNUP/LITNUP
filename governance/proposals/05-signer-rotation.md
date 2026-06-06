# AAIP-NNN: Signer Rotation — [Multisig name] [Add/Remove] [Address]

**Proposal type:** Signer rotation (oracle / treasury / guardian)
**Tier:** Important (10% quorum, 60% supermajority)
**Author:** [handle]

---

## TL;DR

We propose to [ADD | REMOVE | REPLACE] the following signer:

- Multisig: [Foundation Treasury 5-of-9 | Operations 3-of-5 | Oracle 3-of-5 | PauseGuardian 3-of-5]
- Action: [add / remove]
- Address: 0x[...]

---

## Reason for rotation

[One of:]
- [ ] Routine rotation (annual schedule)
- [ ] Compromise / suspected compromise
- [ ] Voluntary departure (signer leaving foundation/role)
- [ ] Performance issue (signer unresponsive in drills)
- [ ] Adding capacity (new founding signer being onboarded)
- [ ] Other: [explain]

---

## New signer details (for additions)

| Field | Value |
|---|---|
| Name | [...] |
| Public handle | [...] |
| Address | 0x... |
| Role | [Foundation / Tech advisor / Community elected / etc.] |
| Jurisdiction | [Country] |
| Hardware setup | [Ledger / Trezor / YubiKey FIDO2] |
| Identity verified by | [KYC provider + date] |
| Independent of foundation | [Yes / No — explain] |

For Foundation Treasury 5-of-9: at least 3 of the 9 must be independent of foundation. After this change, [N] will be independent.

---

## Departing signer details (for removals)

| Field | Value |
|---|---|
| Address | 0x... |
| Role being vacated | [...] |
| Reason for departure | [...] |
| Wind-down period | [...] |
| Token balance (if vested) | [continuing or returned] |

---

## Implementation

### On-chain calldata

For Gnosis Safe-style multisig:
```
function: addOwnerWithThreshold(address owner, uint256 _threshold)
        or removeOwner(address prevOwner, address owner, uint256 _threshold)
        or swapOwner(address prevOwner, address oldOwner, address newOwner)
```

For PerformanceOracle:
```
function: addSigner(address)  or  removeSigner(address)
target:   0x[PerformanceOracle address]
```

For PauseGuardian:
```
function: grantRole(bytes32 role, address account)
        or revokeRole(bytes32 role, address account)
target:   0x[PauseGuardian address]
role:     keccak256("GUARDIAN_ROLE") = 0x...
```

---

## Threshold considerations

After this change:

- Total signers: [N]
- Required threshold: [M]
- Effective ratio: [M-of-N]

Does this change the threshold? [Yes/No]

If yes, justify why the new threshold is appropriate.

---

## Risk assessment

### What if the new signer is malicious?

[Analysis]

### What if the new signer is incompetent?

[Drill schedule + onboarding]

### What if removing the departing signer leaves us insufficient redundancy?

[Backup plan]

### Coordination risk during the rotation window

[Brief downtime in signing capability; mitigations]

---

## Onboarding (for additions)

1. New signer initializes hardware wallet per opsec-key-management.md
2. Foundation legal verifies identity + jurisdiction
3. New signer reviews + signs opsec compliance acknowledgment
4. New signer participates in test signing ceremony with benign tx
5. After all 4 above, this proposal executes

Estimated lead time: 14 days from proposal passage to full integration.

---

## Voting

Vote **FOR** if you trust the new signer (or accept the departure) and believe the rotation strengthens or maintains security.

Vote **AGAINST** if you have concerns about the new signer or believe the existing signer should be retained.

---

## Reporting

The foundation commits to publishing within 30 days of execution:

- On-chain confirmation of the rotation
- Updated signer list on the public ops page
- Confirmation that new signer has completed all onboarding steps
