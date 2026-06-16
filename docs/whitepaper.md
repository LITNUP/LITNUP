# LITNUP — Whitepaper

**Version 0.1 (draft) · 2026-05-05**

> Formal companion to [`litepaper.md`](litepaper.md). This document is written for technical, legal, and economic review. It is the authoritative protocol specification.

---

## Abstract

LITNUP is a permissionless protocol for the verification and incentivization of autonomous trading agents. Agents are deployed by independent operators who post a refundable bond denominated in the protocol's native token, $LITNUP. Capital providers ("stakers") allocate $LITNUP to specific agents as a bonded conviction stake (curation and skin-in-the-game), receiving fungible vault shares that redeem at **principal value only**. Off-chain trading never touches staked $LITNUP: attested PnL is recorded on-chain as a reputation and fee basis and never inflates redeemable assets — staked principal is only ever *reduced* by slashing. Stakers instead earn real, exogenous yield paid by operators as a performance fee in an external settlement asset (the reward token, e.g. USDC), funded through protocol fees and routed via `takeFees()`. Each collected fee is split per attestation between a buyback-and-burn engine on $LITNUP and USDC yield to stakers. The protocol maintains the solvency invariant `litnupToken.balanceOf(vault) >= Σ totalPrincipal` by construction. Oracle-confirmed operator misbehavior or breach triggers slashing of the operator's bond or vault principal. The protocol is governed by veLITNUP vote-escrow with a four-year maximum lock.

This whitepaper specifies the protocol's economic mechanism, contract architecture, oracle design, slashing logic, governance system, and intended migration path to a fully ZK-attested oracle in v2.

---

## 1. Introduction

### 1.1 Background

The AI-agent crypto category exceeded ten billion dollars in market capitalization by mid-2026. Market structure is power-law concentrated: roughly 57% of the category's mcap is held by two projects (Virtuals Protocol and ai16z); approximately 60% of agent tokens have a market capitalization below $100,000.

Despite the category's scale, no incumbent protocol provides on-chain verification of an autonomous agent's trading performance. Token launchpads (e.g., Virtuals, Clanker) issue agent-specific tokens whose price is determined by speculation rather than realized profit. Frameworks (e.g., ai16z's ELIZA) provide off-chain agent infrastructure without standardized performance reporting. Tournament-emission systems (e.g., Bittensor subnets) reward agents in proportion to subnet-internal scoring, decoupled from end-user value.

The result is a market in which capital allocators cannot distinguish productive agents from unproductive ones, a structural friction that limits sustainable capital formation in the category.

### 1.2 Insight

Trading agents are uniquely well-suited to on-chain verification because trading is the only common AI-agent task with costless ground-truth measurement. PnL settles on chains and exchanges; it does not require human grading or subjective evaluation. By anchoring agent compensation, capital allocation, and slashing to settled PnL, LITNUP creates a meritocratic marketplace whose primary unit of account is verifiable.

### 1.3 Design goals

The protocol prioritizes, in descending order:

1. **Verifiability.** Every PnL number routed through the protocol must be cryptographically attestable.
2. **Skin in the game.** Both operators and stakers must bear consequences for agent underperformance.
3. **Permissionlessness.** Any address may deploy an agent. Any address may stake.
4. **Capital efficiency.** Token velocity is high; demand sinks are persistent.
5. **Composability.** Agent vaults use familiar share-based accounting (though they are not a standard ERC-4626 vault: shares redeem at principal and yield is paid separately in USDC); protocol fees flow into standard buyback infrastructure.

### 1.4 Non-goals

The protocol explicitly excludes:

- Token-per-agent accounting (each agent has a vault, not a token).
- Custody of off-chain trading capital. Agents trade on third-party venues; the Protocol verifies their attestations.
- Discretionary curation of agents. The registry is permissionless; quality emerges from staker selection and slashing.
- Human-graded subjective tasks (research, content, etc.). v1 is trading-only; future versions may extend to other settled tasks.

---

## 2. System architecture

### 2.1 Components

The protocol comprises seven primary contracts. They are currently deployed and verified on Base Sepolia testnet (chain id 84532); mainnet on Base (chain id 8453) is targeted for v1 but is **not yet deployed**:

| Contract | Role |
|---|---|
| `LitnupToken` | ERC20 + ERC20Votes + ERC20Permit, capped at 10⁹ * 10¹⁸ wei |
| `AgentRegistry` | Permissionless agent enrollment; operator bond custody; slashing |
| `StakingVault` | Per-agent share-based vaults (principal-redeemable); USDC yield distribution; PnL recorded for reputation; fee plumbing |
| `PerformanceOracle` | EIP-712 multi-signer PnL attestation |
| `BuybackBurn` | Fee revenue → swap → burn pipeline |
| `VotingEscrow` | 4-year max lock for veLITNUP governance weight |
| `MerkleAirdrop` | Distribution of seasonal airdrops |

Off-chain, an open-source Python runtime ("agent-runtime") provides reference strategies, EIP-712 attestation signing, and venue adapters for paper-trading and (optionally) live execution.

### 2.2 Data flow

The end-to-end data flow for a typical agent is:

```
Off-chain runtime ──── price feed (CoinGecko/Pyth) ───── strategy
       │                                                    │
       │                                                    ▼
       │                                            position decision
       │                                                    │
       └────────────── execution venue (Hyperliquid, Aerodrome, ...)
                                  │
                                  ▼
                           settled trade
                                  │
                                  ▼
                  ┌─── PnL aggregation (off-chain) ────┐
                  │                                     │
                  ▼                                     ▼
            EIP-712 attestation              high-water-mark monitoring
                  │                                     │
                  ▼                                     ▼
       PerformanceOracle.applyAttestation     PerformanceOracle.triggerDrawdownSlash (if breach)
                  │                                     │
                  ▼                                     ▼
       StakingVault.recordPnl (reputation)    StakingVault.slashVault
       StakingVault.takeFees (USDC)                   │
                  │                                     │
        ┌─────────┴─────────┐                          ▼
        ▼                   ▼                   $LITNUP principal routed
   USDC yield to        USDC to                    to BuybackBurn
     stakers           BuybackBurn                      │
                          │                             │
                          └──────── BuybackBurn.swapAndBurn ────┘
                                  │
                                  ▼
                           supply reduction
```

### 2.3 Trust assumptions

The protocol's security depends on the following assumptions:

1. **Honest oracle quorum.** A threshold (3-of-5 on testnet; configurable by governance, with a higher M-of-N targeted for mainnet; ZK-proven by v2) of oracle signers behave correctly. The reported performance fee is derived from this threshold-signed attestation — it is **not** trustlessly recomputed from raw on-chain PnL, and this is an explicit trust assumption.
2. **Correctness of price feeds and venues used by the oracle.** The oracle's PnL computation is only as good as its input data. Curated venue whitelist mitigates.
3. **Soundness of the cryptographic primitives** (EIP-712, ECDSA, keccak256).
4. **Operational security of signers.** Hardware-key-backed signers; geographic and entity diversity.
5. **Base network liveness** during attestation windows. v2 omnichain reduces this dependency.

These assumptions are made explicit so that compromise modes are bounded and recoverable. See §10 for a full risk taxonomy.

---

## 3. Token economics

### 3.1 Supply

| Parameter | Value |
|---|---|
| Total supply (cap) | 1,000,000,000 * 10¹⁸ |
| Initial mint | 100% to Foundation treasury at TGE; redistributed per allocation table below |
| Inflation | None |
| Burn mechanism | `burn()` and `burnFrom()` reduce `totalSupply` |

### 3.2 Allocation

| Allocation | Fraction | Vesting |
|---|---:|---|
| Public sale (LBP / Echo) | 5% | Unlocked at TGE |
| Airdrop S1 | 10% | 30% TGE; 70% over 4 months (vest-into-stake is planned/roadmap, not yet implemented in contracts) |
| Initial DEX liquidity | 3% | LP-locked 12 months |
| Ecosystem incentives | 17% | Linear M0–M24 |
| Team | 15% | 1-year cliff, 36-month linear |
| Investors (angel + seed + strategic) | 15% | 1-year cliff, 24-month linear |
| Treasury (DAO-controlled) | 15% | Multisig at TGE; DAO at month 12 |
| Foundation reserve | 10% | 24-month time lock |
| Future airdrops + community | 10% | Streaming, governance-gated |

### 3.3 Demand sinks

| Sink | Mechanism |
|---|---|
| Operator bonds | ≥10,000 $LITNUP per agent enrollment; locked while agent active |
| Vault stake | Locked while staked; 7-day cooldown to unstake |
| veLITNUP | Up to 4-year lock for governance weight + fee rebates |
| Buyback & burn | a per-attestation fraction (`toBuybackBps`) of each collected protocol fee → buy → permanent supply reduction (the remainder streams to stakers as USDC yield; a 50/50 split is an illustrative default, not a hardcoded protocol parameter) |

### 3.4 Fee model

The performance fee is **reported** per attestation via the threshold-signed EIP-712 oracle message (see §5.1); it is not trustlessly recomputed from raw on-chain PnL. The fee is collected as **real reward-token (USDC)** pulled from the operator (`feePayer`) by `StakingVault.takeFees()` — nothing is credited unless the transfer succeeds. There is **no** global protocol-level `buybackBps` governance parameter on-chain. Each attestation carries:

- `feeAmount`: the reported performance fee, in reward-token (USDC) units, to pull from the operator.
- `toBuybackBps` (bound in the signature, range 0–10,000): the fraction of *this* fee directed to `BuybackBurn`; the remainder streams to the agent's stakers as USDC yield.

For a single collected fee:

```
toBuyback = feeAmount * toBuybackBps / 10_000     // USDC sent to BuybackBurn
toStakers = feeAmount - toBuyback                  // USDC distributed to stakers
```

`toStakers` accrues to active stakers through a per-share reward accumulator and is claimed separately in USDC — it does **not** enter the vault's $LITNUP principal and does **not** change share price (shares always redeem at principal, only reduced by slashing). `toBuyback` is sent to `BuybackBurn`. If a vault has no active stakers, the entire fee is routed to buyback so no funds are stranded. Any "50/50" split shown in examples is an illustrative default, not a hardcoded value.

### 3.5 Buyback flywheel mechanics

The figures below are **illustrative / forward-looking** sensitivity examples, not achieved results. Annual buyback expressed in $LITNUP token-units burned (with all fee flows denominated in the USDC reward token):

```
annualBurnTokens = feeRevenue_USD × buybackShare / tokenPrice_USD
                 = [TVL × R × f × b] / P
```

For an illustrative TVL = $50M, R = 0.25, f = 0.15, b = 0.50, FDV = $200M ⇒ tokenPrice ≈ $0.20:

```
annualBurnUSD     = $50M × 0.25 × 0.15 × 0.50 = $937,500
annualBurnTokens  = $937,500 / $0.20 = 4,687,500 $LITNUP
% supply / year   = 4,687,500 / 1,000,000,000 = 0.47%
```

Here `b` (the buyback share) is the **per-attestation** `toBuybackBps`, illustratively averaged at 0.50; it is not a single hardcoded protocol parameter.

Sensitivity is approximately linear in TVL and quadratic-ish in token price (since holding TVL fixed, lower token price means more tokens burned per dollar of fee). The reflexive feedback — lower price → faster supply reduction → upward pressure — is the canonical buyback flywheel observed in Maker, Hyperliquid, and others.

---

## 4. Vault accounting (StakingVault.sol)

### 4.1 Per-agent state

```solidity
struct Vault {
    uint128 totalPrincipal;     // real $LITNUP backing this agent's stakers
    uint128 totalShares;        // outstanding shares (active + cooling-down)
    uint128 rewardShares;       // active shares only — the base that earns USDC yield
    uint64  cooldown;           // unstake cooldown duration in seconds (default 7 days)
    int256  cumulativePnl;      // attested cumulative PnL (reputation/fee basis only)
    uint256 accRewardPerShare;  // accumulated reward-token (USDC) per active share, scaled by 1e18
}
```

Solvency holds by construction: principal only enters via `stake()` and only leaves via `unstakeComplete()` / `slashVault()`, so `litnupToken.balanceOf(vault) >= Σ_agents totalPrincipal` at all times.

### 4.2 Share conversion

```
sharesIssued(amount) = amount * totalShares / totalPrincipal   if totalShares > 0
                     = amount                                   if first deposit

assetsRedeemed(shares) = shares * totalPrincipal / totalShares
```

Multiplication-then-division is performed using OpenZeppelin's `Math.mulDiv` to avoid intermediate overflow on `uint256` arithmetic. Because share price never *rises* (PnL never inflates principal), `totalShares >= totalPrincipal` always; redemption rounds down and a `ZeroShares` guard backstops dust deposits. Internal accounting (not `balanceOf`) is used to defeat donation/inflation attacks.

### 4.3 PnL application (reputation only)

`recordPnl(agentId, int256 delta)` is oracle-only and **moves no assets**. It accumulates `cumulativePnl`, which serves purely as the agent's on-chain reputation/ranking signal and informs the off-chain fee basis. This is the safe replacement for the repudiated v1 `applyPnl`, which inflated redeemable assets with $LITNUP that did not exist (the v1 insolvency bug). Redeemable principal is therefore never increased by attested profit; it is only ever reduced by slashing.

### 4.4 Staking operations

| Function | Effect |
|---|---|
| `stake(agentId, amount)` | Pulls `amount` $LITNUP from caller; mints `sharesIssued(amount)`. Enforces `perVaultCap` (default 1,000,000 $LITNUP per vault). |
| `unstakeInit(agentId, shares)` | Moves `shares` from active to cooling-down; sets `unlockAt = now + cooldown`. Cooling shares stop earning yield but remain redeemable at principal and slashable. |
| `unstakeComplete(agentId)` | After cooldown, burns pending shares; transfers `assetsRedeemed(shares)` $LITNUP (principal) to caller. |
| `claimRewards(agentId)` | Transfers the staker's accrued reward-token (USDC) yield. |
| `recordPnl(agentId, delta)` | Oracle-only; accumulates `cumulativePnl` (reputation/fee basis); moves no assets. |
| `takeFees(agentId, feeAmount, toBuybackBps, feePayer)` | Oracle-only; pulls `feeAmount` USDC from `feePayer`, sends `feeAmount*toBuybackBps/10000` to buyback and accrues the rest to stakers as USDC yield. |
| `slashVault(agentId, amount)` | Oracle-only; transfers `amount` $LITNUP principal from vault to burn sink (share price drops honestly). |

### 4.5 Cooldown rationale

The 7-day cooldown serves three purposes:

1. **Prevents JIT yield/slash gaming.** A staker cannot stake immediately before a fee distribution and unstake immediately after, nor exit instantly to dodge a pending slash (cooling shares remain slashable).
2. **Reduces oracle MEV.** Attesters cannot collude with stakers to time yield capture at the expense of long-term holders.
3. **Aligns staker time horizon with agent strategy.** Conviction staking that signals durable support benefits from non-momentary capital.

The cooldown is per-vault configurable; default 7 days, capped at 30.

---

## 5. Oracle design (PerformanceOracle.sol)

### 5.1 v1: multi-signer EIP-712

The v1 oracle is a `t-of-n` multi-signer scheme over EIP-712 typed data. The threshold is governance-configurable; the testnet deployment runs 3-of-5, with a higher M-of-N targeted for mainnet. The reported PnL and performance fee reflect a threshold of signers agreeing on a number — this is "attested," not "trustless," and a future version aims to root attestations in venue/TEE/ZK settlement proofs.

**Domain:**

```
EIP712Domain {
    name: "LITNUPOracle"
    version: "1"
    chainId: <chain id at execution>
    verifyingContract: <oracle contract address>
}
```

**Attestation type:**

```
Attestation {
    uint256 agentId
    int256  pnlDelta
    uint256 feeAmount       // performance fee in reward token (USDC), pulled from feePayer
    uint16  toBuybackBps    // per-attestation fee split (0–10000); bound in the signature
    address feePayer        // operator address that approved the fee pull
    uint64  epoch
    uint64  deadline
}
```

Binding `toBuybackBps` and `feePayer` inside the signed struct means a relayer cannot alter the fee split or who pays (the v1 design left `toBuybackBps` as an unsigned call parameter).

**Verification flow:**

1. Compute typed-data digest via `_hashTypedDataV4`.
2. For each provided signature, recover signer.
3. Reject if signer not in `isSigner` set.
4. Reject if signer ≤ previous signer (sorted-ascending requirement deduplicates).
5. Count valid signatures; require ≥ `threshold`.
6. Mark `(agentId, epoch)` as executed; revert on replay.
7. Apply the attestation: `StakingVault.recordPnl` (reputation) and, if `feeAmount > 0`, `StakingVault.takeFees` (real USDC).

Slashing of staker principal (`applySlash`) and of operator bonds (`slashBond`) is **separately and independently** threshold-signed under distinct EIP-712 types with their own replay namespaces, so seizing funds can never ride on a fee attestation or a single key.

### 5.2 Signer set governance

Signers may be added or removed by the `SIGNER_MANAGER_ROLE` (controlled by Foundation multisig at TGE; transitions to DAO timelock by month 12).

### 5.3 v2: ZK-attested compute

Long-term, the multi-sig oracle is replaced by a ZK proof of correct PnL computation. The roadmap target is:

- Proof of trade settlement on each whitelisted venue (Hyperliquid, Aerodrome, Pendle).
- Aggregation of per-venue settlements into a per-agent epoch PnL.
- A SNARK proving the aggregation is correct without revealing the strategy.

Migration risks include proof-system audit cost, prover latency, and the necessity of fallback to multi-sig if proofs become unavailable. The migration is gated by economic and engineering audit.

### 5.4 Drawdown slashing

The oracle off-chain monitors high-water-mark equity per agent. When equity drops below `(1 - drawdownSlashBps/10000) * HWM` and remains below for one full attestation cycle, the oracle triggers `vault.slashVault(agentId, amount)` where:

```
amount = vaultTotalAtBreach * drawdownSlashSizeBps / 10_000
```

Default: `drawdownSlashBps = 2500` (25%), `drawdownSlashSizeBps = 1000` (10%). Slashed assets flow to the burn sink.

---

## 6. Governance (VotingEscrow.sol)

### 6.1 vote-escrow design

Locks of $LITNUP for up to four years confer linearly-decaying voting weight:

```
voting_weight(user) = locked_amount * time_remaining / MAX_LOCK
                    where MAX_LOCK = 4 years
```

Locks are aligned to weekly boundaries (week start = Thursday 00:00 UTC). One active lock per user; subsequent calls extend or top up.

### 6.2 Operations

| Function | Effect |
|---|---|
| `createLock(amount, unlockTime)` | Locks `amount` until `unlockTime` (week-aligned, ≤ 4 years out). |
| `increaseAmount(amount)` | Adds tokens to the lock without changing unlock time. |
| `extendLock(newUnlockTime)` | Extends to a later unlock time. |
| `withdraw()` | After unlock, returns full locked amount. |
| `balanceOf(user)` | Current voting weight (linear decay). |

### 6.3 Governance scope

Governance via veLITNUP controls:

- The oracle signer set and signing threshold (M-of-N), via `SIGNER_MANAGER_ROLE`
- Vault configuration: `perVaultCap` (default 1,000,000 $LITNUP), per-vault cooldown (≤ 30 days), and the buyback/burn sink address
- Whitelist of execution venues and price oracles
- Treasury allocation
- Emergency pause activation (subject to higher quorum)
- Future contract deployments / migrations

Note: there is **no** global on-chain `buybackBps` or `protocolFeeBps` parameter. The fee split (`toBuybackBps`) is set per attestation and bound in the oracle signature; the performance-fee level itself is reported per attestation, not a stored governance parameter.

### 6.4 Future enhancement

A point-history checkpoint mechanism (Curve-style) is planned for a v1.x release to enable accurate `totalSupply` of voting weight for off-chain tools. The current `totalSupply()` returns the locked-token total as a conservative upper bound.

---

## 7. Airdrop infrastructure (MerkleAirdrop.sol)

Each airdrop season is a distinct deployment of `MerkleAirdrop` with:

- A merkle root committing to (index, account, amount) triples
- A claim deadline (typically 90 days)
- A sweep recipient for unclaimed tokens (typically Treasury)

Standard OpenZeppelin merkle proof verification; bitmap-based claim tracking; sweep-after-deadline.

For Season 1 (10% of supply at TGE), allocation is:

- 30% claimable directly at TGE
- 70% streamed over four months. "Vest-into-stake" (automatically directing the streamed portion into a per-recipient stake position) is a **planned/roadmap** anti-dump design and is **not yet implemented in the contracts**; the streaming schedule and any vest-into-stake mechanics are subject to governance decisions pre-TGE.

---

## 8. Capital structure & legal

The Protocol is intended to be operated by the LITNUP Foundation, a Cayman Islands foundation company (currently **in formation**) with no equity holders. The founder and chair is Arthur Romanov; foundation members do not own equity in the foundation.

The $LITNUP token is intended to be a utility token with the on-chain functions described in §3.3. **No legal opinions currently exist; counsel review and formal token-classification opinions are planned** before mainnet, and the intended utility-token classification is subject to applicable counsel review in each relevant jurisdiction (it should not be relied upon as a present legal conclusion). Sale and marketing exclude U.S. persons and sanctioned jurisdictions.

A separate development subsidiary (**planned / in progress — not yet formed**) may be established, with operations to be governed under arms-length licensing or services agreements with the Foundation. No such subsidiary exists today.

Full legal analysis: [`plan/legal-checklist.md`](../plan/legal-checklist.md).

---

## 9. Roadmap

| Quarter | Milestone |
|---|---|
| Q2 2026 | MVP contracts on Base Sepolia. First reference agents. Litepaper public. |
| Q3 2026 | Public testnet. 50+ agents enrolled. Phantom-TVL competition. Audit kickoff. |
| Q4 2026 | Mainnet on Base. Pre-seed close. KOL push. Tier-3 CEX listings. |
| Q1 2027 | Tier-2 CEX listings. v2 cross-chain spec finalized. veLITNUP live. |
| Q2 2027 | Tier-1 CEX target window. ZK oracle prototype. |
| Q3 2027 | DAO transition: foundation council → on-chain governance. |
| Q4 2027 | v2 deploy: omnichain agents, ZK attestations, permissionless venues. |

The roadmap is metric-gated, not calendar-gated. TGE will not occur before audit completion AND a minimum testnet TVL target.

---

## 10. Risk taxonomy

Documented in [`plan/risk-register.md`](../plan/risk-register.md). Highlights:

- **Smart-contract risk** (Critical) — mitigated by deposit caps and bug bounty; no third-party audit has been completed or commissioned, and independent audit(s) are planned before mainnet
- **Oracle compromise** (Critical) — mitigated by multi-sig, geographic diversity, emergency pause, ZK migration
- **Premature TGE** (High) — mitigated by KPI-gated launch, bootstrap-first capital plan
- **Regulatory action** (High) — mitigated by foundation structure, geofencing, and planned counsel review (no MiCA compliance is claimed or in place)
- **Cliff sell pressure** (Medium) — mitigated by transparent unlock dashboard and OTC desks; vest-into-stake is a planned/roadmap mitigation not yet implemented in contracts
- **Agent gaming** (Medium) — mitigated by mark-to-fair-price, drawdown caps, whitelisted venues

---

## 11. References

- Curve Finance — vote-escrow primitive, 2020
- Hyperliquid HLP / user vault docs — share-based trader vault precedent, 2024–2026
- Bittensor whitepaper — subnet emission model, 2023
- OpenZeppelin Contracts — base implementations of ERC20Votes, EIP-712, AccessControl
- ERC-4626 — Tokenized Vault Standard
- EIP-712 — Typed structured data hashing and signing
- ChainCatcher — analysis of AI agent token concentration, 2026

---

## 12. Glossary

- **Agent**: an autonomous (or semi-autonomous) trading program registered in `AgentRegistry` and represented by an `agentId`.
- **Operator**: the entity controlling an agent's enrollment and runtime; holds the `controller` address.
- **Bond**: $LITNUP posted by an operator at enrollment, slashable on misbehavior.
- **Staker**: any address holding a positive share balance in any agent's vault.
- **Attestation**: a signed message certifying a PnL delta for an agent over an epoch.
- **Epoch**: a monotonic counter per agent; one attestation per epoch maximum.
- **Slashing**: permanent reduction of bond or vault assets, typically routed to the burn sink.
- **veLITNUP**: the linear-decay voting weight derived from a $LITNUP lock in `VotingEscrow`.
- **Burn sink**: an address whose balance is reduced via the token's `burn` mechanism, permanently removing tokens from supply.
- **Drawdown**: the percentage decline of an agent's equity from its all-time high.

---

*This whitepaper is a working draft. Review by securities counsel, smart-contract auditors, and economic auditors precedes the version intended for TGE.*
