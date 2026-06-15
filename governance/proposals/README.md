# Governance Proposal Templates

This directory contains canonical templates for the most common governance actions on LITNUP. Each template is designed to drop into the LITNUP Forum (or a Snapshot space) and produce a complete, executable proposal.

## How proposals work

1. **Discussion phase (7 days minimum):** Idea posted as a Forum thread; community comments
2. **Snapshot vote (3 days):** Off-chain signal vote among veLITNUP holders
3. **On-chain proposal (Timelock 48h):** If signal vote passes, on-chain proposal queued to Timelock
4. **Execution:** After Timelock delay, anyone can call `execute()`

Proposals must:
- Reference exactly one of the templates below
- Include a discussion-phase URL with at least 7 days of community comments
- Include the on-chain calldata (or generate it from the template's parameter table)

## Template index

| File | Use for |
|---|---|
| `01-parameter-tune.md` | Adjusting governance-tunable protocol parameters (drawdown threshold, slash size, fee bps, vault cap, cooldown duration) |
| `02-treasury-spend.md` | Disbursing treasury funds (grants, contractor payments, ecosystem awards) |
| `03-emergency-pause.md` | Triggering PauseGuardian to pause whitelisted contract functions |
| `04-add-pauseguardian-action.md` | Adding a (target, selector) pair to PauseGuardian's whitelist |
| `05-signer-rotation.md` | Adding/removing oracle signers, treasury multisig signers, or guardian signers |
| `06-emission-redirect.md` | Redirecting EmissionScheduler recipient weights |
| `07-policy-revision.md` | Changing the published policy documents (treasury, opsec, incident runbook) |

## Proposal-naming convention

`AAIP-NNN: <Brief Imperative Title>`

(AAIP = LITNUP Improvement Proposal. NNN auto-increments.)

Example: `AAIP-014: Reduce Drawdown Threshold from 25% to 22%`

## What we won't accept

- Proposals with less than 7 days of discussion
- Proposals that bypass templates
- Proposals from accounts with <100 veLITNUP weight (anti-spam threshold; can be paid for by lifetime $LITNUP stakers >50k tokens)
- Multi-action proposals that bundle unrelated changes

## Required veLITNUP weights for execution

| Tier | Quorum | Approval threshold | Examples |
|---|---|---|---|
| Routine | 5% | Simple majority | Most parameter tunes, treasury spends < $250k |
| Important | 10% | 60% supermajority | Treasury spends $250k-$2M, signer rotations, emission redirects |
| Constitutional | 20% | 67% supermajority | Treasury policy revisions, drawdown threshold changes >5pp, slashing size changes >5pp |

## Execution mechanics

After Snapshot vote passes, an executor (any veLITNUP holder) submits the on-chain proposal to the Timelock. The Timelock enforces a 48h delay. After delay, anyone can call `execute()` to apply the change.

Failed Timelock execution doesn't refund the proposer's gas. We accept this tradeoff — bad proposals should die before reaching Timelock.
