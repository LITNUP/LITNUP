# AAIP-NNN: Add PauseGuardian whitelist entry — [Contract.Function]

**Proposal type:** Add or revoke PauseGuardian whitelist entry
**Tier:** Important (10% quorum, 60% supermajority)
**Author:** [handle]
**Discussion thread:** [URL]
**Snapshot vote:** [URL]

---

## TL;DR

We propose to **[ADD | REVOKE]** the following entry from the PauseGuardian whitelist:

- Target: `[contract address]`
- Selector: `[4-byte selector]`
- Function: `[ContractName].[functionName]([args])`

If passed, this entry [becomes / ceases to be] callable by the PauseGuardian on a 3-of-5 guardian approval.

---

## Background

The PauseGuardian is an emergency-pause multisig that can call only **whitelisted** (target, selector) pairs. This whitelist is itself governed: adding or removing entries requires a Timelock proposal with a 60% supermajority approval.

This proposal is one of those whitelist updates.

Current whitelist entries (as of [date]):

| # | Contract | Function | Action ID hash |
|---|---|---|---|
| 1 | StakingVault | `pause()` | 0x... |
| 2 | StakingVault | `unpause()` | 0x... |
| 3 | PerformanceOracle | `pauseAttestations()` | 0x... |
| 4 | ... | ... | ... |

---

## Why add (or revoke) this entry?

[Detailed reasoning. Include:]

- The threat scenario this entry would mitigate
- Why a normal Timelock proposal would be too slow for that threat
- Why this specific function is the right one (vs. a more invasive alternative)
- The risk that the guardian misuses this entry (overpause, false-positive)
- How the function's behavior is reversible if pause is wrong

---

## Function audit

### What the function does

[Read the function in the contract; explain what it changes]

### What it CANNOT do

[Confirm it cannot move funds, mint, escalate privileges, etc.]

### How a malicious 3-of-5 guardian could misuse it

[Honest threat-model analysis]

### How quickly the misuse can be reversed

[Method to undo: another guardian action, governance, etc.]

---

## Implementation

### On-chain calldata

```
target: 0x[PauseGuardian address]
function: allowAction(address, bytes4)  // or revokeAction
args:
  target:   0x[whitelisted contract]
  selector: 0x[4-byte selector]
```

cast calldata:
```bash
cast calldata "allowAction(address,bytes4)" 0x[contract] 0x[selector]
```

Action ID (kept for record):
```
keccak256(abi.encodePacked(target, selector)) = 0x[hash]
```

---

## Risk assessment

| Risk | Severity | Mitigation |
|---|---|---|
| Guardians collude to over-pause | Low (3-of-5 + 5-day approval window) | Public visibility of guardian actions; reputational cost |
| Guardian keys compromised | Low if opsec policy followed | Hardware-key requirement; 24h approval window |
| Whitelisted function has unintended behavior | Audited | Function reviewed by [auditor] on [date] |
| Pause causes user harm by halting critical function | Acceptable | Reversible by counter-action; guardian liability |

---

## Voting

Vote **FOR** if you believe the protocol benefits from having this circuit breaker available.

Vote **AGAINST** if you believe this entry creates more attack surface than it removes.

Vote **ABSTAIN** if you don't have an opinion.

---

## Operational follow-up

If passed:

1. Guardians will be notified to update their internal runbooks
2. The PauseGuardian's public dashboard will show the new entry
3. A drill will exercise the new pause within 30 days

If revoked:

1. Guardians will be notified
2. The entry's removal will be visible on-chain
3. Open approvals (if any) are auto-cleared
