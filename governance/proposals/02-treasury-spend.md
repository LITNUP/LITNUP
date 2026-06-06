# AAIP-NNN: Treasury Spend — [Recipient/Project] for [USD amount]

**Proposal type:** Treasury spend (Tier: Routine | Important | Constitutional)
**Author:** [handle]
**Discussion thread:** [URL]
**Snapshot vote:** [URL]

---

## TL;DR

We propose to spend [AMOUNT] from the foundation treasury to [RECIPIENT] for [PURPOSE].

Total cost: $[X] USD-equivalent (currently [Y] USDC + [Z] LITNUP at VWAP).

---

## Recipient details

| Field | Value |
|---|---|
| Recipient name | [...] |
| Recipient address | [0x...] |
| Recipient type | [Individual / Org / Multisig] |
| Jurisdiction | [Country] |
| KYC status | [Verified by [provider] on YYYY-MM-DD] |
| Conflict-of-interest disclosure | [If recipient is connected to any foundation member, disclose here] |

---

## Purpose

[1-3 paragraphs on what the funds are for, what deliverables are expected, and why this spend creates value for the protocol]

---

## Deliverables

| # | Deliverable | Acceptance criteria | Deadline |
|---|---|---|---|
| 1 | [...] | [...] | [date] |
| 2 | [...] | [...] | [date] |

---

## Payment schedule

| Tranche | Amount | Trigger | Form |
|---|---:|---|---|
| 1 | $[X] | On execution | USDC |
| 2 | $[X] | Deliverable 1 acceptance | USDC |
| 3 | $[X] | Deliverable 2 acceptance | USDC + 6mo-vested LITNUP |

Total: $[total]

---

## Source of funds

[Which treasury bucket?]

- [x] Operating treasury (USDC)
- [ ] Strategic reserve (ETH/BTC)
- [ ] Ecosystem grants budget (AGENTIC)
- [ ] Insurance fund (AGENTIC, only for protocol losses)

---

## Implementation

### Calldata

```
For Tier 1:
  target: 0x[OpsMultisig address]
  signers: 2-of-5
  function: USDC.transfer(recipient, amount)

For Tier 2/3 (timelocked):
  target: 0x[Timelock]
  delay: 48h
  payload: USDC.transfer(recipient, amount)
```

### Tier-specific approval

| Tier | Threshold | Pre-conditions |
|---|---|---|
| Routine (≤$25k/item, ≤$200k/month) | 2-of-5 ops multisig | None |
| Large operational ($25k-$250k) | 3-of-5 ops + 24h notice | Public notice posted |
| Strategic ($250k-$2M) | 5-of-9 board + 7-day notice | Reasoning published |
| Constitutional (>$2M) | veAGENTIC vote (60% / 67%) | 14-day notice + 48h timelock |

---

## Risk assessment

### Counterparty risk
[Recipient creditworthiness; legal exposure; KYC quality]

### Execution risk
[What if the deliverables don't arrive? Clawback provisions?]

### Reputation risk
[How does this look to outside observers?]

### Concentration risk
[Is this one of many deals with the same recipient? Aggregate exposure?]

---

## Alternatives considered

[At least 2 alternatives the proposer considered and rejected]

1. **[Alternative]:** Rejected because [...]
2. **[Alternative]:** Rejected because [...]

---

## Disclosure

The proposer:
- [ ] Has no financial interest in the recipient
- [ ] Has the following financial interest: [...]

The recipient:
- [ ] Has no relationship to foundation members
- [ ] Has the following relationship: [...]

---

## Voting

Vote **FOR** if you believe this spend creates expected value > cost for the protocol.
Vote **AGAINST** if you believe the cost is too high or the recipient is wrong.
Vote **ABSTAIN** if you have insufficient information.

---

## Reporting

Within 30 days of execution, the proposer (or successor) commits to publishing:

- Wallet receipt confirmations
- Deliverable status
- Any deviation from plan
- Updated risk assessment

Failure to report within 30 days triggers automatic clawback consideration in the next governance cycle.
