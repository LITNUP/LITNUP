# AAIP-NNN: [Action] [Parameter] from [old] to [new]

**Proposal type:** Parameter tune (Tier: Routine | Important | Constitutional — pick one)
**Status:** Draft → Discussion → Snapshot → Timelock → Executed
**Author:** [Your handle / address]
**Discussion thread:** [URL — must have at least 7 days of comments]
**Discussion start:** [YYYY-MM-DD]
**Snapshot vote:** [URL]
**On-chain proposal id:** [Timelock proposal id, set after queuing]

---

## TL;DR

[2-3 sentence plain-English summary]

We propose to change [PARAMETER NAME] from [OLD VALUE] to [NEW VALUE].
Reason: [briefest possible rationale].
Expected impact: [briefest possible expected outcome].

---

## Background

[What does this parameter control? What is its current value? Why was that value chosen originally?]

Reference current value:
- Contract: [`StakingVault.sol` / `PerformanceOracle.sol` / etc.]
- Function: [`setPerVaultCap` / `setCooldown` / etc.]
- Variable name: [e.g., `perVaultCap`]
- Current value: [decimal + unit]
- Last changed: [date or "never since deployment"]

---

## Proposal

We propose to change:

| Parameter | Current | Proposed | Δ |
|---|---:|---:|---:|
| `perVaultCap` | 1,000,000 LIT | 1,500,000 LIT | +50% |

The change will be effected by calling:

```
StakingVault.setPerVaultCap(1_500_000 ether)
```

at address `0x...` (StakingVault deployment on Base mainnet, see `addresses.json`).

---

## Rationale

[Why this change? Why now? What data supports the change?]

Provide:
- Quantitative justification (charts, on-chain metrics, simulator outputs)
- Comparable protocol parameter choices for context
- A short failure analysis: what's the worst case if this change is harmful?

---

## Risk assessment

### What could go wrong

[Honest list of failure modes]

### Reversibility

[How easily can this be reversed? Is there a one-way effect?]

### Stakeholder impact

| Cohort | Effect |
|---|---|
| Stakers | [...] |
| Operators | [...] |
| Treasury | [...] |
| Token holders (non-staking) | [...] |

---

## Implementation

### On-chain calldata

```
target:  0x[StakingVault address]
value:   0
data:    0x[ABI-encoded call to the relevant setter, hex-formatted]
```

You can verify the calldata by running the following in Foundry / cast:

```
cast calldata "setPerVaultCap(uint128)" 1500000000000000000000000
```

### Timelock parameters

- Target: [contract address]
- Function: [function selector]
- Args: [args]
- Predecessor: bytes32(0)
- Salt: [computed from proposal id]
- Delay: 48 hours

### Verification post-execution

After execution:
1. Read the parameter on-chain to confirm new value
2. Verify event `[EventName]` was emitted with expected args
3. Verify dependent dashboards / dApp show updated value

---

## Voting

Vote **FOR** if you believe the proposed change improves protocol economics.

Vote **AGAINST** if you believe the current value is correct or the proposed value is worse.

Vote **ABSTAIN** if you understand the change but have no strong preference.

---

## Updates / amendments

| Date | Change |
|---|---|
| [YYYY-MM-DD] | Initial draft |

---

## Footnotes

- This template is for parameter changes only. For structural changes, see other templates.
- Multi-parameter bundled changes are NOT permitted; file separate proposals.
- Time-limited parameter changes (e.g., 30-day temporary increase) require a follow-up proposal scheduled at the same time as this one.
