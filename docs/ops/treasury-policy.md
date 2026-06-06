# Treasury Management Policy

**Status:** Draft v1 · last updated 2026-05-09
**Audience:** Foundation board, multisig signers, treasury operators
**License:** CC-BY-4.0 (excerpts may be quoted with attribution)

---

## Purpose

This policy defines how the LITNUP foundation treasury is held, what it can be spent on, who decides, and how spending is audited. It exists to **make treasury behavior predictable in advance** so token holders, contributors, and the community can hold us accountable.

If we deviate from this policy, we publish the deviation, the reasoning, and the new policy. We do not deviate quietly.

---

## Treasury composition (target steady-state)

The foundation treasury target composition, calculated quarterly:

| Asset | Target % | Range | Rationale |
|---|---:|---|---|
| **USDC** | 35% | 25-50% | Operational runway, payroll, audits, vendors |
| **ETH** | 25% | 15-35% | Strategic reserve, gas, on-chain ops |
| **$LIT** | 30% | 20-40% | Native token; held NOT for sale, but for governance & strategic use |
| **BTC** | 5% | 0-15% | Long-tail reserve |
| **Stablecoin diversification** (USDT, DAI) | 5% | 0-10% | Counterparty diversification of stables |

We rebalance quarterly **only if** any asset has drifted >10 percentage points outside its target. We do NOT actively trade. We are a treasury, not a hedge fund.

**Specific exclusions:**
- No leveraged positions, ever
- No NFTs (treasury asset, not protocol-related ones)
- No "earn yield" via rehypothecation lending platforms (Aave/Compound base yields ok up to 10% of stables)
- No memecoins, including memecoin "investments" labeled as ecosystem
- No private investments in other crypto projects unless approved via supermajority governance vote

---

## Spending authority

The treasury has four spending tiers. Each requires different approval:

### Tier 1 — Routine operations (daily / weekly)
**Up to $25K per item, $200K per month**
**Approval:** 2-of-5 ops multisig (treasury operator + COO/founder)

Covers: payroll, hosting, vendor invoices, bug bounty payouts (auto-up-to-$10K), regular audit installments, conferences, travel, software subscriptions.

### Tier 2 — Large operational (monthly)
**$25K to $250K per item, $1M per quarter**
**Approval:** 3-of-5 ops multisig + 24h public notice

Covers: full audit engagements, major vendor contracts, one-off security work, marketing campaigns, hiring bonuses, facility leases.

### Tier 3 — Strategic (quarterly)
**$250K to $2M per item**
**Approval:** 5-of-9 foundation board multisig + 7-day public notice + reasoning published

Covers: market-maker inventory loans, partner integration grants, ecosystem grants programs, large hiring (founding-team additions), liquidity pair changes, major OTC sales.

### Tier 4 — Constitutional (rare)
**Above $2M, or any change to treasury policy itself**
**Approval:** veAGENTIC vote (60% quorum, 2/3 majority) + 14-day public notice + 48h timelock

Covers: changes to vesting schedules, changes to emission schedule, foundation domicile changes, treasury policy revisions, any change to allocation percentages above the ±10pp range.

---

## On-chain treasury custody

All native-token and stablecoin treasury holdings live in:

- **Foundation Safe (5-of-9 multisig)** on Base — primary cold storage
- **Operations Safe (3-of-5 multisig)** on Base — Tier 1 + 2 spending hot wallet
- **Time-locked Treasury Safe** on Base — non-routine spending, gated by 48h Timelock contract
- **Cold backup** — air-gapped, geographically distributed; receives 70%+ of treasury after each rebalance

Signer requirements:
- All signers use hardware wallets (Ledger Nano X or comparable)
- All signers have identity verified by foundation legal counsel
- All signers reside in different jurisdictions (no two signers in the same country)
- Signers are NOT all foundation board members — at least 3 must be independent (technical advisors / community-elected)

---

## Burn-rate disclosure

We publish monthly burn rate:

- Salaries / contractors (anonymized count + total)
- Audits / security
- Hosting / infra
- Legal / accounting
- Marketing
- Other

Published in the quarterly transparency report. Granular monthly figures available on request to seed investors per their MFN clause.

**Maximum acceptable burn:** 12 months of runway must always be available at current burn. If we cross under that threshold, we publicly disclose, freeze hiring, and propose a capital plan within 30 days.

---

## Tokens held by treasury — usage rules

Treasury holds 25% of total supply (250M $LIT) at TGE, vesting per the foundation schedule. These tokens are NOT for sale. They are for:

1. **Governance reserves.** Treasury votes its tokens via veAGENTIC according to council direction; never for self-dealing proposals.
2. **Emission backing.** Source of truth for the EmissionScheduler, which streams to staker/operator rewards over 24mo.
3. **Strategic OTC.** If we need fiat (e.g., to fund a strategic partner integration that USDC reserves don't cover), we sell tokens via OTC, NOT on AMM. Always with 7-day public notice. Always with a published price floor (e.g., 30-day VWAP).
4. **Liquidity rebalancing.** Topping up Aerodrome / partner LP positions when ranges drift.

Treasury tokens are NEVER:
- Sold on AMMs (creates sell pressure invisibly)
- Used as collateral (creates liquidation risk)
- Lent (creates rehypothecation risk)
- Staked into our own vaults (creates conflict of interest with stakers)

---

## OTC sale policy

When the treasury sells $LIT, the policy is:

- **Buyer eligibility:** Long-term-aligned partner (institutional, not retail). Min $250K ticket. Disclosed identity to the foundation board (may be anonymous to public if the buyer requests, but identity is logged).
- **Pricing:** 30-day VWAP floor + buyer-paid premium for the strategic value of the relationship.
- **Lockup:** 12-month cliff + 24-month linear vest. Treasury OTC buyers vest the same as seed investors.
- **Public notice:** 7-day public notice including ticker, amount, price, and counterparty class (e.g., "tier-1 market-maker", "institutional fund", "liquidity provider").
- **Post-trade reporting:** Within 24h, on-chain transaction + transparency report entry.

We will NOT do:
- Discount sales below VWAP (signals weakness)
- Block trades to "ecosystem partners" without lockup
- Backdoor allocations to influencers (zero exceptions)

---

## Insurance fund

5% of supply (50M $LIT) is reserved for the InsuranceFund contract. Per protocol policy:

- **Funding:** Initial seed of 50M $LIT + ongoing top-up from 5% of all protocol fees
- **Disbursements:** Only from `DISBURSER_ROLE`, gated through governance
- **Use cases:**
  - Partial reimbursement of slashed stakers on first-time slashing events (50% on first slash, 0% on subsequent)
  - Protocol-level losses from oracle bugs / smart contract issues (post-audit-confirmed)
  - Bug bounty payouts above the standard $250K cap

We do NOT use the insurance fund for:
- Operational expenses
- Marketing
- Anything not directly related to user/protocol losses

---

## Quarterly transparency report

Each quarter, the foundation publishes a treasury transparency report covering:

- Opening + closing balance per asset
- Inflows (fee revenue, OTC sales, grants received) by source
- Outflows by Tier (1/2/3/4) + by category
- Burn-rate vs runway
- Any rebalancing actions taken
- Any policy deviations with reasoning
- Material risks (counterparty, regulatory, etc.) the treasury is aware of

Reports are published on /transparency on the same day they're filed with the foundation board.

---

## Audit + assurance

- **Annual financial audit:** by a recognized accounting firm (Deloitte / KPMG / PWC tier or crypto-specialized like Armanino)
- **Quarterly proof-of-reserves:** Merkle-tree-of-balances published on-chain; off-chain wallets attested
- **Multisig signer rotations:** Annually, with public disclosure of signer IDs (or pseudonyms with verifiable consistency)

---

## Conflicts of interest

Foundation board, employees, and core contributors must:

- Disclose any beneficial ownership above 0.1% of $LIT, $ETH/Base ecosystem tokens that compete with us, or other tokens held in the treasury
- Recuse from any vote materially affecting their disclosed holdings
- Publish any sales of foundation-allocated tokens in advance (7-day notice for >$50K worth)
- Decline gifts/benefits from third parties seeking treasury allocation above $250 in value

---

## Emergency provisions

In case of force majeure (regulatory action, major exchange failure, signing-key compromise, foundation legal emergency):

- The 5-of-9 multisig has authority to move treasury assets without normal approval flow
- Emergency moves must be ratified by veAGENTIC vote within 30 days (if validators conclude the emergency was genuine, the action stands)
- Emergency moves are publicly disclosed within 48h with reasoning

There is no scenario in which treasury assets can be "swept" or moved without leaving a public on-chain trail.

---

## Policy revisions

This document is versioned. Revisions require:

- Tier 4 approval (veAGENTIC vote, 60% quorum, 2/3 majority)
- 14-day public comment period before vote
- Diff published showing changes from previous version
- Reasoning document explaining each change

Last revision: 2026-05-09 (initial draft).

— The LITNUP Foundation
