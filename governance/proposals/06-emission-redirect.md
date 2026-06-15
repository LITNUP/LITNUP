# AAIP-NNN: Redirect Emission to [New Recipient] @ [Weight]

**Proposal type:** Emission scheduler weight change
**Tier:** Important (10% quorum, 60% supermajority)
**Author:** [handle]

---

## TL;DR

We propose to redirect emissions from the EmissionScheduler:

| Recipient | Current weight | Proposed weight | Δ |
|---|---:|---:|---:|
| [recipient A] | 4000 bps (40%) | 3000 bps (30%) | -10pp |
| [recipient B] | 6000 bps (60%) | 5000 bps (50%) | -10pp |
| [recipient C] (new) | 0 bps | 2000 bps (20%) | +20pp |

Total weight: 10000 bps. Sum of changes: 0.

---

## Background

The EmissionScheduler streams emissions over 24 months (730 days) per the launch tokenomics. Recipients are usually:

- Staking-Rewards distributor (operator + staker rewards)
- Insurance fund top-up
- Ecosystem grants pool
- veLITNUP bonus emissions

Each has a basis-point weight summing to 10000 bps (100%).

This proposal changes those weights.

---

## Why redirect?

[Reasoning. Examples:]

- "Operator rewards are currently capturing more emission than necessary. The market shows that operators are bidding strongly even at lower yields. Redirecting to staker rewards strengthens the staker yield curve and improves TVL flow."
- "We propose introducing a new recipient — [Builder Grants Program] — to fund integration partnerships. Current emission flows have less marginal impact than what a fresh grants program could achieve."

---

## Quantitative justification

[Charts, simulator outputs, market data supporting the change]

| Metric | Current | Projected |
|---|---|---|
| Operator rewards / month | $X | $Y |
| Staker yield (avg) | A% | B% |
| Insurance fund top-up | $X / month | $Y / month |
| Etc. | ... | ... |

---

## Implementation

### Calldata for each recipient change

```
For each recipient:
  target: 0x[EmissionScheduler]
  function: setRecipient(address recipient, uint16 weight)
  args: (recipient, newWeight)
```

cast calldata samples:
```bash
cast calldata "setRecipient(address,uint16)" 0x[recipient_a] 3000
cast calldata "setRecipient(address,uint16)" 0x[recipient_b] 5000
cast calldata "setRecipient(address,uint16)" 0x[recipient_c] 2000
```

### Execution order

Execute in this order to avoid temporary weight overflow:
1. Reduce A from 4000 → 3000
2. Reduce B from 6000 → 5000
3. Add C at 2000

Sum after each step: 10000, 9000, 9000+2000=10000. No overflow.

---

## Risk assessment

### What if the new weights produce unexpected behavior?

[Analysis]

### Reversibility

The next governance cycle can always revert. EmissionScheduler weights are governance-tunable.

### Effect on already-streamed emissions

Past emissions are NOT clawed back. Only future emissions are affected.

### Effect on operator/staker incentives

[Honest analysis. Reduced operator rewards may reduce operator participation. Reduced staker rewards may reduce TVL.]

---

## Voting

Vote **FOR** if the proposed weights better serve the protocol's near-term goals.

Vote **AGAINST** if the current weights produce a healthier flywheel.

---

## Sunset clause

This change [does | does not] include a sunset clause. If sunset:

- Effective: [date X to date Y]
- After sunset, weights revert to: [previous values]

If no sunset, the next governance cycle can always change weights again.
