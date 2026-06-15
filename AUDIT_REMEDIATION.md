# LITNUP — internal audit & remediation report

**Date:** 2026-06-13 · **Scope:** all Solidity contracts, the Python agent runtime, the TypeScript
SDK, the subgraph, deployment, and documentation.

This is an **internal pre-audit remediation pass**, not a substitute for an independent third-party
audit (which remains a mainnet gate — see §6). It documents a top-to-bottom review, the issues found,
and the fixes applied. Everything below is reproducible: `cd contracts && forge test` (157 tests green).

---

## 1. Headline verdict

The protocol was real, substantial engineering wrapped around **two fatal problems** and several
investor-facing misstatements. Both fatal problems are now fixed; the misstatements are corrected.

| Problem | Before | After |
|---|---|---|
| **Vault solvency** | `applyPnl(+delta)` inflated `totalAssets` with no tokens entering, while fees/withdrawals/slashing moved *real* tokens out → bank-run insolvency on the first profitable epoch | Stake redeems at **real principal** (slash-adjusted); PnL is reputation-only; yield is **real USDC** from operator fees. Fuzzed invariant proves `balance ≥ obligations`. |
| **"Provable PnL"** | Marketed as provable; actually a committee signing an arbitrary number | Re-labelled honestly as **attested** PnL; `toBuybackBps`+`feePayer` bound into the EIP-712 struct; slashing is threshold-signed. v2 goal: root attestations in venue/TEE/ZK data. |
| **False claims** | "Audited by Spearbit/ToB/Cantina", "Live on Base Sepolia" | Removed; replaced with an honest status note. Nothing is deployed; no audit is complete. |

## 2. The solvency redesign (the core fix)

The off-chain trading never touches staked $LITNUP, so crediting "profit" in $LITNUP that no token
backs was insolvent by construction. The new model:

- **Principal-redeemable stake.** Shares redeem at real principal; share price starts at 1.0 and only
  drops on slashing. `applyPnl` → `recordPnl` (reputation/fee basis; moves no assets).
- **Real, exogenous USDC yield.** Operators pay performance fees in USDC via
  `takeFees(agentId, feeAmount, toBuybackBps, feePayer)` (pulls real tokens). Split: stakers' USDC
  accumulator + `BuybackBurn` (USDC → $LITNUP → burn). Non-circular.
- **Honest slashing.** Moves real $LITNUP to the burn sink; threshold-signed (`applySlash`,
  `slashBond`), never a single key.
- **Enforced invariant** (`contracts/test/Invariants.t.sol`): fuzzed across
  stake/recordPnl/takeFees/slash/unstake/claim — `litnupToken.balanceOf(vault) ≥ Σ principal` and
  reward-token balance ≥ owed rewards. This is the exact property the old design violated.

## 3. Findings → remediation (verified)

| # | Severity | Finding | Status |
|---|---|---|---|
| 1 | Critical | StakingVault insolvent by design (phantom PnL) | **Fixed** — redesign §2 |
| 2 | Critical | Single-EOA "god mode": all roles on deployer at deploy | **Fixed** — deploy script hands roles to Safe+Timelock and renounces deployer |
| 3 | High | "Provable PnL" overstated; `toBuybackBps` not signed | **Fixed** — bound into EIP-712; re-labelled |
| 4 | High | `BuybackBurn` slippage from caller input → sandwich | **Fixed** — keeper-gated, `expectedAmountOut>0`, pausable |
| 5 | High | `triggerDrawdownSlash` single-key seizure | **Fixed** — replaced by threshold-signed `applySlash` |
| 6 | High | `EmissionScheduler` retroactive reweight steals past emissions | **Fixed** — checkpointed accrual + stop switch |
| 7 | High | `PauseGuardian` bricks on repeat-pause; never deployed; core not pausable | **Fixed** — clears approvals on reset; cooldown guard; core contracts now Pausable; deployed+wired |
| 8 | High | Timelock governs nothing | **Fixed** — deploy grants CONFIG/SIGNER_MANAGER to Timelock |
| 9 | High | README false audit/deployment claims | **Fixed** — corrected |
| 10 | Medium | `Vesting.revoke` under-pays the already-vested amount | **Fixed** — freezes schedule as fully-vested at `vested` |
| 11 | Medium | `AgentRegistry.slash` arbitrary sink; residual bond stranded; bond-slash path dead | **Fixed** — fixed sink, recoverable residual, oracle `slashBond` wired |
| 12 | Medium | `_toShares` rounds to zero | **Fixed** — `ZeroShares` guard; price can't rise so dust can't strip |
| 13 | Medium | Unchecked int256→int128 / uint256→uint128 downcasts | **Fixed** — `SafeCast` everywhere |
| 14 | Medium | `MerkleAirdrop` single-hash leaf; no root setter | **Fixed** — OZ double-hash leaf; `setMerkleRoot` (locked after first claim) |
| 15 | Medium | `RewardsDistributor` no recovery; proof portable across channels | **Fixed** — `recoverChannelFunds`; `channelId` bound into leaf |
| 16 | Medium | `InsuranceFund` decimal-blind shared cap | **Fixed** — per-token decimal-aware caps |
| 17 | Medium | FAQ tokenomics summed to 110% | **Fixed** — 100%, aligned to `tokenomics.md` |
| 18 | Low/Info | Broken legacy `deploy/Deploy.s.sol` (imports deleted file); naming drift (LitToken/veAGENTIC/alphagentic); SDK addresses undefined; subgraph won't compile; `cli.py oracle sign` crash; build didn't compile (empty `lib/`) | **Fixed** — see §4 |

Verification during the audit *downgraded* several reported "highs" (e.g. arbitrary-sink and the
downcasts require a trusted role) — this table reflects the de-hyped, verified severities.

## 4. Build / test / integration

- **Toolchain:** Foundry 1.7.1; pinned `openzeppelin-contracts@v5.1.0` + `forge-std@v1.9.4` in
  `contracts/lib`. `forge build` clean; **`forge test` → 157 passed / 0 failed**, incl. fuzzed
  invariants. (Was: didn't compile at all.)
- **EIP-712 pipeline:** Python signer ↔ SDK ↔ Solidity now agree on the 7-field `Attestation`
  (`agentId, pnlDelta, feeAmount, toBuybackBps, feePayer, epoch, deadline`). Python round-trip tests pass.
- **SDK:** `react.ts` addresses resolve (camelCase keys); ABIs regenerated from build artifacts;
  rebranded to LITNUP.
- **Subgraph:** uint64 decode + `LockToppedUp.added` + `PnlRecorded` handler fixed (run
  `graph codegen && graph build` against deployed ABIs before indexing).
- **Runtime:** `cli.py oracle sign` fixed; signer deadline widened to outlast quorum gathering.

## 5. What changed for the investor story (be honest about this)

Stakers do **not** receive the agent's trading PnL converted to $LITNUP (that was never real).
They get: (a) a curation/governance role, (b) **real USDC yield** from operator performance fees on
agents they back, and (c) shared downside via slashing. Token value accrues via **real USDC fees →
buy-and-burn**. This is the version that survives diligence.

## 6. Mainnet gates (NOT yet satisfied — required before mainnet)

- [ ] Independent external smart-contract audit + remediation.
- [ ] Legal/securities opinion (staking on managed performance ≈ Howey; Cayman + geofencing reviewed by counsel).
- [ ] 5-of-9 Safe with hardware keys; real oracle signer set.
- [ ] Monitoring/alerting + incident-response & pause runbook.
- [ ] The traction the market asked for: 2–3 real agents posting live attestations on testnet, verified contracts, a public dashboard.

See [`deploy/DEPLOYMENT.md`](deploy/DEPLOYMENT.md) for the full runbook.
