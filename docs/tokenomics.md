# $LITNUP Tokenomics

> Working draft — locked numbers require legal + economic audit before TGE.

## 1. Headline numbers

- **Total supply:** 1,000,000,000 $LITNUP (capped, no inflation)
- **Initial circulating at TGE:** ~110M (11%)
- **Initial DEX liquidity:** 30M (3%)
- **Public sale (LBP/Echo):** 50M (5%)
- **Airdrop S1 at TGE:** 30M (3%; S1 total is 10% over 4 months)

## 2. Allocation table (full)

| Bucket | Tokens | % | At TGE | Vest schedule |
|---|---:|---:|---:|---|
| Public sale | 50,000,000 | 5% | 100% | None — fully unlocked |
| Airdrop S1 | 100,000,000 | 10% | 30% | 30% TGE, 70% over 4 months linear (vest into stake) |
| Initial DEX liquidity | 30,000,000 | 3% | 100% (locked in pool) | Pool tokens locked 12 months |
| Ecosystem incentives | 170,000,000 | 17% | 0% | Linear M0–M24, ~7M/mo, governance can pause |
| Team | 150,000,000 | 15% | 0% | 1y cliff, then 36-mo linear (default vest into stake) |
| Investors (all rounds) | 150,000,000 | 15% | 0% | 1y cliff, then 24-mo linear |
| Treasury (DAO) | 150,000,000 | 15% | 0% | Unlocked at TGE but DAO-multisig controlled |
| Foundation reserve | 100,000,000 | 10% | 0% | 24-mo time-lock, then governance control |
| Future airdrops + community | 100,000,000 | 10% | 0% | Streaming, governance-gated S2/S3 |
| **Total** | **1,000,000,000** | **100%** | | |

## 3. Estimated circulating supply over time

Assumes TGE at month 0. "Circulating" = liquid + airdrop-claimed-but-not-vested-into-stake. Numbers are approximate.

| Month | Estimated circulating | % of total |
|---:|---:|---:|
| 0 (TGE) | ~110M | 11% |
| 3 | ~145M | 14.5% |
| 6 | ~220M | 22% |
| 9 | ~265M | 26.5% |
| 12 (cliff begins) | ~380M | 38% |
| 18 | ~550M | 55% |
| 24 | ~720M | 72% |
| 36 | ~900M | 90% |
| 48 | ~1B | 100% |

**Cliff risk:** month 12 unlocks an estimated 75M from team + investor + treasury cliff endings. This is the highest-risk single moment. Mitigations:

1. **Vest-into-stake.** Default contract for team/investor unlocks deposits the unlocked tokens directly into a staking position rather than the wallet. Receivers can override but the default is sticky.
2. **OTC desks queued.** Have Wintermute / GSR ready to absorb large blocks at slight discount, paid in stables out of treasury.
3. **Buyback escalation.** Pre-fund a one-month buyback acceleration from treasury bridging the cliff.
4. **Transparent dashboard.** Publish real-time unlock + dump/no-dump tracker; market prices in the cliff before it lands.

## 4. Token utility (demand sinks)

### 4.1 Agent enrollment bonds

Every new agent locks ≥10,000 $LITNUP. Slashed on misbehavior. With 500 agents at year 1, this sinks 5M $LITNUP permanently (until unbonding) — small in absolute terms but signals quality.

### 4.2 Stake on agents

Stakers' $LITNUP is locked in the StakingVault while staked, plus 7-day cooldown. Target: $50M+ TVL by year 1 = ~25–50M $LITNUP locked at typical prices.

### 4.3 veAGENTIC governance lock

4-year vote-escrow for governance weight + fee rebates + bonus airdrop allocations. Modeled on Curve's veCRV. Aim for 30–50% of circulating supply locked in ve at steady state.

### 4.4 Buyback & burn (deflationary)

50% of all protocol fees → BuybackBurn contract → buys $LITNUP on DEX → burns. The other 50% pays stakers in-kind ($LITNUP re-distribution). Estimated buy pressure scales linearly with TVL × agent gross profit.

**Steady-state estimate (conservative):**
- TVL: $50M (year 1 target)
- Average annualized agent return: 25% (selection effect — bad agents get unstaked)
- Average protocol fee rate: 15% of profit
- Annual fees: $50M × 25% × 15% = $1.875M
- Buyback portion: 50% = $937.5k/year buy pressure
- At a $200M FDV, this is ~0.5% of supply burned annually

Flywheel: more TVL → more fees → more burn → higher token price → more agents and stakers → more TVL.

## 5. Fee model

Two fees:

1. **Performance fee.** Charged per attestation epoch on positive PnL. Configurable per agent (default 10%, capped at 50%). Paid in $LITNUP.
2. **Withdrawal fee.** 0% for cooldown-respecting withdrawals; 1% emergency-withdrawal fee for users who skip cooldown (planned v1.5 — not in v1).

**No deposit fees.** No protocol-level take on entry. Friction-free staking is critical for early growth.

## 6. Airdrop design (anti-sybil)

S1 (10%, at TGE): allocated to:

- Testnet stakers and agent operators (real activity; not just connected wallets)
- Galxe / Layer3 / Zealy quest completers (filtered)
- Discord / Telegram OG members with verified history
- KOL allocation (limited; vested only)
- Pendle / Hyperliquid / Aerodrome power users (cross-pollination)

**Anti-sybil filters applied:**
1. Minimum on-chain age (90+ days)
2. Minimum gas spent on Base / Ethereum (≥$50)
3. Wallet clustering analysis (no airdrop to clusters of >5 wallets behaving identically)
4. Twitter linkage required for tier-2/3 allocations
5. Drop-off threshold: top 80% by score get linear allocation, bottom 20% get fixed nominal

S2 (5%, M+6): post-mainnet behavior — actual stakers, agent operators, ve-lockers.
S3 (5%, M+12): governance participants, contributors.

## 7. Governance

- **Voting token:** $LITNUP delegated, OR veAGENTIC (4y lock) for boosted weight (4× max).
- **Proposal threshold:** 100k $LITNUP delegated.
- **Quorum:** 4% of supply delegated.
- **Voting period:** 7 days.
- **Timelock on execution:** 48 hours (governance-controlled timelock can be raised to 14 days for sensitive changes).
- **Emergency multisig:** 5-of-9 founder + advisor, retains pause-only authority during the first 6 months post-mainnet, then dissolved.

## 8. Comparison to peers

| Metric | $LITNUP | $TAO | $VIRTUAL | $AI16Z |
|---|---:|---:|---:|---:|
| Total supply | 1B (capped) | 21M (capped) | 1B (capped) | 1.1B |
| Inflation | None | High (block reward) | None | None |
| Buyback & burn | Yes (fee-funded) | No | No | No |
| Stakeable | Yes (per-agent) | Yes (subnet) | No (token-only) | No |
| Vote-escrow | Yes (4yr) | No | No | No |
| Fee accrual | Yes (50% to burn, 50% to stakers) | Block rewards | Tax on launches | None |

The token combines deflationary pressure (capped + burn) with a productive use (stake on real performers) — a combination that none of the existing top-tier comps offer.

## 9. Sensitivity analysis

How sensitive is the buyback flywheel to assumptions?

| Scenario | TVL | Avg return | Fee rate | Annual buyback $ | % supply burned/yr at $200M FDV |
|---|---:|---:|---:|---:|---:|
| Conservative | $20M | 15% | 10% | $150k | 0.075% |
| Base | $50M | 25% | 15% | $937k | 0.47% |
| Optimistic | $200M | 30% | 15% | $4.5M | 2.25% |
| Stretch | $500M | 35% | 20% | $17.5M | 8.75% |

Even in the conservative scenario the flywheel is positive. Optimistic-case 2%+ annual burn against a capped supply is the kind of math that supports sustained reflexivity.

## 10. Open questions

- **Should fees be denominated in stablecoins or $LITNUP?** Currently designed in-kind ($LITNUP). Consider stable-denom for institutional appeal.
- **Should ve-locks have transfer NFTs (like Curve)?** Probably yes — secondary market improves capital efficiency.
- **Foundation buyback fund: how large?** Currently 100M (10% of supply). Could be smaller if confident in fee flywheel.
- **Stake migration on agent withdrawal:** UX TBD.
- **Insurance fund seed:** likely 1–2% from treasury after first 6 months of mainnet stability.

These resolve through DAO governance and economic audit pre-TGE.
