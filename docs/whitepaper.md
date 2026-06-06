# LITNUP — Whitepaper

**Version 0.1 (draft) · 2026-05-05**

> Formal companion to [`litepaper.md`](litepaper.md). This document is written for technical, legal, and economic review. It is the authoritative protocol specification.

---

## Abstract

LITNUP is a permissionless protocol for the verification and incentivization of autonomous trading agents. Agents are deployed by independent operators who post a refundable bond denominated in the protocol's native token, $LITNUP. Capital providers ("stakers") allocate $LITNUP to specific agents, receiving fungible vault shares whose price tracks the agent's settled, attestable PnL. A multi-signer oracle attests PnL on a regular cadence, applying gains and losses to the per-agent vault and routing a configurable protocol fee to a buyback-and-burn engine on $LITNUP. Sustained drawdown beyond a configurable threshold triggers proportional slashing of staked assets; oracle-confirmed operator misbehavior triggers slashing of the operator's bond. The protocol is governed by veAGENTIC vote-escrow with a four-year maximum lock.

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
5. **Composability.** Agent vaults are ERC-4626-compatible; protocol fees flow into standard buyback infrastructure.

### 1.4 Non-goals

The protocol explicitly excludes:

- Token-per-agent accounting (each agent has a vault, not a token).
- Custody of off-chain trading capital. Agents trade on third-party venues; the Protocol verifies their attestations.
- Discretionary curation of agents. The registry is permissionless; quality emerges from staker selection and slashing.
- Human-graded subjective tasks (research, content, etc.). v1 is trading-only; future versions may extend to other settled tasks.

---

## 2. System architecture

### 2.1 Components

The protocol comprises seven primary contracts, deployed on Base (chain id 8453) for v1:

| Contract | Role |
|---|---|
| `LitToken` | ERC20 + ERC20Votes + ERC20Permit, capped at 10⁹ * 10¹⁸ wei |
| `AgentRegistry` | Permissionless agent enrollment; operator bond custody; slashing |
| `StakingVault` | Per-agent share-based vaults; PnL marking; fee plumbing |
| `PerformanceOracle` | EIP-712 multi-signer PnL attestation |
| `BuybackBurn` | Fee revenue → swap → burn pipeline |
| `VotingEscrow` | 4-year max lock for veAGENTIC governance weight |
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
       StakingVault.applyPnl                  StakingVault.slashVault
       StakingVault.takeFees                          │
                  │                                     │
                  ▼                                     ▼
           share price update              tokens routed to BuybackBurn
                  │                                     │
                  └──────── BuybackBurn.swapAndBurn ────┘
                                  │
                                  ▼
                           supply reduction
```

### 2.3 Trust assumptions

The protocol's security depends on the following assumptions:

1. **Honest oracle quorum.** A threshold (≥3 of 5 in v1; ≥9 of 13 by month 12; ZK-proven by v2) of oracle signers behave correctly.
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
| Airdrop S1 | 10% | 30% TGE; 70% over 4 months, vest-into-stake |
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
| veAGENTIC | Up to 4-year lock for governance weight + fee rebates |
| Buyback & burn | 50% of every protocol fee → buy → permanent supply reduction |

### 3.4 Fee model

Two fee parameters per agent:

- `protocolFeeBps` (set at enrollment, capped at 5,000 bps = 50%): fraction of gross profit taken as protocol fee per attestation.
- `buybackBps` (governed at the protocol level, default 5,000 bps = 50%): fraction of the protocol fee routed to `BuybackBurn` (vs. retained in vault as additional yield to stakers).

For a single attestation epoch with positive `pnlDelta`:

```
feeOnGross   = pnlDelta * protocolFeeBps / 10_000
toBuyback    = feeOnGross * buybackBps / 10_000
toStakers    = feeOnGross - toBuyback
```

`toStakers` remains in the vault and lifts share price; `toBuyback` is sent to `BuybackBurn`.

### 3.5 Buyback flywheel mechanics

Annual buyback expressed in token-units burned:

```
annualBurnTokens = TVL_USD × avgAgentReturn × protocolFeeRate × buybackShare / tokenPrice_USD
                 = [TVL × R × f × b] / P
```

For TVL = $50M, R = 0.25, f = 0.15, b = 0.50, FDV = $200M ⇒ tokenPrice ≈ $0.20:

```
annualBurnUSD     = $50M × 0.25 × 0.15 × 0.50 = $937,500
annualBurnTokens  = $937,500 / $0.20 = 4,687,500 AGENTIC
% supply / year   = 4,687,500 / 1,000,000,000 = 0.47%
```

Sensitivity is approximately linear in TVL and quadratic-ish in token price (since holding TVL fixed, lower token price means more tokens burned per dollar of fee). The reflexive feedback — lower price → faster supply reduction → upward pressure — is the canonical buyback flywheel observed in Maker, Hyperliquid, and others.

---

## 4. Vault accounting (StakingVault.sol)

### 4.1 Per-agent state

```solidity
struct Vault {
    uint128 totalAssets;     // total $LITNUP backing this agent's stakers
    uint128 totalShares;     // outstanding shares for this agent's vault
    uint64  lastAttestation; // timestamp of last PnL attestation
    uint64  cooldown;        // unstake cooldown duration in seconds
}
```

### 4.2 Share conversion

```
sharesIssued(amount) = amount * totalShares / totalAssets    if totalShares > 0
                     = amount                                 if first deposit

assetsRedeemed(shares) = shares * totalAssets / totalShares
```

Multiplication-then-division is performed using OpenZeppelin's `Math.mulDiv` to avoid intermediate overflow on `uint256` arithmetic. Rounding is in the protocol's favor (down) on issuance; same on redemption.

### 4.3 PnL application

`applyPnl(agentId, int128 delta)` mutates `totalAssets` directly:

- If `delta > 0`: `totalAssets += delta`.
- If `delta < 0`: `totalAssets = max(0, totalAssets - |delta|)`.

A guard caps `|delta| ≤ totalAssets / 2` per call. This bounds the damage of a malicious or buggy oracle.

### 4.4 Staking operations

| Function | Effect |
|---|---|
| `stake(agentId, amount)` | Pulls `amount` from caller; mints `sharesIssued(amount)` to caller. |
| `unstakeInit(agentId, shares)` | Moves `shares` from active to pending; sets `unlockAt = now + cooldown`. |
| `unstakeComplete(agentId)` | Burns pending shares; transfers `assetsRedeemed(shares)` to caller. |
| `applyPnl(agentId, delta)` | Oracle-only; mutates `totalAssets`. |
| `takeFees(agentId, fee, bps)` | Oracle-only; routes `fee*bps/10000` to buyback, retains rest. |
| `slashVault(agentId, amount)` | Oracle-only; transfers `amount` from vault to burn sink. |

### 4.5 Cooldown rationale

The 7-day cooldown serves three purposes:

1. **Prevents JIT staking around attestations.** A staker cannot stake immediately before a positive attestation and unstake immediately after.
2. **Reduces oracle MEV.** Attesters cannot collude with stakers to time profit-taking at the expense of long-term holders.
3. **Aligns staker time horizon with agent strategy.** Strategies that mean-revert over multi-day windows benefit from non-momentary capital.

The cooldown is per-vault configurable; default 7 days, capped at 30.

---

## 5. Oracle design (PerformanceOracle.sol)

### 5.1 v1: multi-signer EIP-712

The v1 oracle is a `t-of-n` multi-signer scheme over EIP-712 typed data. Default at testnet: 3-of-5; transitioning to 5-of-7, then 9-of-13 by month 12.

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
    uint256 feeOnGross
    uint64  epoch
    uint64  deadline
}
```

**Verification flow:**

1. Compute typed-data digest via `_hashTypedDataV4`.
2. For each provided signature, recover signer.
3. Reject if signer not in `isSigner` set.
4. Reject if signer ≤ previous signer (sorted-ascending requirement deduplicates).
5. Count valid signatures; require ≥ `threshold`.
6. Mark `(agentId, epoch)` as executed; revert on replay.
7. Apply attestation to `StakingVault`.

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

Governance via veAGENTIC controls:

- `protocolFeeBps` global cap (currently 5,000 bps)
- `buybackBps` (currently 5,000 bps)
- Whitelist of execution venues and price oracles
- Treasury allocation
- Oracle signer set rotation (above a configurable threshold of changes)
- Emergency pause activation (subject to higher quorum)
- Future contract deployments / migrations

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
- 70% streamed into a per-recipient stake position over four months ("vest-into-stake"). This anti-dump mechanism is the current default; recipients may opt out if specific design decisions are made by governance pre-TGE.

---

## 8. Capital structure & legal

The Protocol is intended to be operated by [LITNUP Foundation Ltd.], a Cayman Islands foundation company with no equity holders. Founders are members of the foundation; they do not own equity in the foundation.

The $LITNUP token is a utility token with the on-chain functions described in §3.3. It is not a security, an investment contract, or a unit of a collective investment scheme. Final classification is subject to applicable counsel review in each relevant jurisdiction. Sale and marketing exclude U.S. persons and sanctioned jurisdictions.

A separate Marshall Islands or Delaware entity may be used as a development subsidiary, with operations governed under arms-length licensing or services agreements with the Foundation.

Full legal analysis: [`plan/legal-checklist.md`](../plan/legal-checklist.md).

---

## 9. Roadmap

| Quarter | Milestone |
|---|---|
| Q2 2026 | MVP contracts on Base Sepolia. First reference agents. Litepaper public. |
| Q3 2026 | Public testnet. 50+ agents enrolled. Phantom-TVL competition. Audit kickoff. |
| Q4 2026 | Mainnet on Base. Pre-seed close. KOL push. Tier-3 CEX listings. |
| Q1 2027 | Tier-2 CEX listings. v2 cross-chain spec finalized. veAGENTIC live. |
| Q2 2027 | Tier-1 CEX target window. ZK oracle prototype. |
| Q3 2027 | DAO transition: foundation council → on-chain governance. |
| Q4 2027 | v2 deploy: omnichain agents, ZK attestations, permissionless venues. |

The roadmap is metric-gated, not calendar-gated. TGE will not occur before audit completion AND a minimum testnet TVL target.

---

## 10. Risk taxonomy

Documented in [`plan/risk-register.md`](../plan/risk-register.md). Highlights:

- **Smart-contract risk** (Critical) — mitigated by 3-stage audit plan, deposit caps, bug bounty
- **Oracle compromise** (Critical) — mitigated by multi-sig, geographic diversity, emergency pause, ZK migration
- **Premature TGE** (High) — mitigated by KPI-gated launch, bootstrap-first capital plan
- **Regulatory action** (High) — mitigated by foundation structure, geofencing, MiCA whitepaper
- **Cliff sell pressure** (Medium) — mitigated by vest-into-stake, transparent unlock dashboard, OTC desks
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
- **veAGENTIC**: the linear-decay voting weight derived from a $LITNUP lock in `VotingEscrow`.
- **Burn sink**: an address whose balance is reduced via the token's `burn` mechanism, permanently removing tokens from supply.
- **Drawdown**: the percentage decline of an agent's equity from its all-time high.

---

*This whitepaper is a working draft. Review by securities counsel, smart-contract auditors, and economic auditors precedes the version intended for TGE.*
